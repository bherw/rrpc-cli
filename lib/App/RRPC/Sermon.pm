package App::RRPC::Sermon;

use aliased 'DateTime::Format::ISO8601';
use App::RRPC::Util -all;
use Kavorka;
use Moo;
use MooX::StrictConstructor;
use namespace::autoclean;
use Params::Util qw(_INSTANCE);
use Path::Tiny;
use POSIX qw(ceil);
use Scalar::Andand;
use Type::Utils qw(class_type);
use Types::Standard qw(Maybe Bool Int Str);

use overload
	bool => sub { 1 },
	'cmp' => sub { shift->cmp(@_) };

my @METADATA_ATTRS = qw(
	identifier recorded_at series scripture_focus scripture_reading
	scripture_reading_might_be_focus speaker title
);

has 'app', is => 'rw', weak_ref => 1, required => 1;
has 'id', is => 'rw', isa => Int;
has 'identifier', is => 'rw', isa => Str, required => 1;
has [qw(scripture_reading title)], is => 'rw', isa => Str, required => 1;
has [qw(scripture_focus series)], is => 'rw', isa => Maybe[Str];
has 'scripture_reading_might_be_focus', is => 'rw', isa => Bool, default => 0;

has 'audio_peaks_file',
	is => 'lazy',
	builder => method {
		my $tmpfile = TempFile->new(suffix => '.json');
		audiowaveform(
			-i => $self->audio_file,
			-o => $tmpfile,
			'--pixels-per-second' => ceil $self->app->audio_peaks_resolution / $self->duration
		);
		require JSON;
		my $json = JSON->new->decode($tmpfile->slurp);
		$tmpfile->spew(pack 's*', @{$json->{data}});
		$tmpfile;
	};

has 'duration',
	is => 'lazy',
	builder => method {
		require Audio::TagLib;
		Audio::TagLib::FileRef->new($self->audio_file->stringify)->audioProperties->length
	};

my $PgDateTime = class_type('DateTime')
	->plus_coercions(Str, sub {
			require DateTime::Format::Pg;
			DateTime::Format::Pg->parse_datetime($_)
	});

has 'recorded_at',
	is => 'lazy',
	isa => $PgDateTime,
	coerce => 1,
	builder => method {
		local $_ = $self->identifier;
		/^\d{4}-\d\d-\d\d[AP]M$/
			or die "Couldn't determine recorded_at from identifier, please set it explictly: $_";
		s/AM/T10:00:00/;
		s/PM/T18:00:00/;
		ISO8601->parse_datetime($_);
	};

has 'speaker',
	is => 'lazy',
	isa => Str,
	default => method { $self->app->default_speaker };

has 'archive2_file',
	is => 'lazy',
	builder => method {
		my $path = $self->archive2_file_path;
		return $path if -f $path;

		die "Final archive file for " . $self->identifier . ' missing';
	};

has 'mp3_file',
	is => 'lazy',
	builder => method {
		my $app = $self->app;
		my $path = $self->mp3_file_path;

		if (!-f $path) {
			require App::RRPC::TempFile;
			$path = App::RRPC::TempFile->new;
			my $wav = $self->wav_file;

			lame(
				'--preset' => 'voice',
				-q => 0,
				'--tt' => $self->title,
				'--ta' => $self->speaker,
				'--tl' => $app->mp3_album,
				'--ty' => $self->recorded_at->year,
				$wav,
				$path,
			);
		}

		$path;
	};

has 'wav_file',
	is => 'lazy',
	builder => method {
		my $path = $self->wav_file_path;
		
		if (!-f $path) {
			require App::RRPC::TempFile;
			$path = App::RRPC::TempFile->new;
			my $archive2 = $self->archive2_file;

			# Decode flac, overwriting the empty temp file.
			flac '-d', '-f', $archive2, '-o' => $path;
		}

		$path;
	};

method audio_file {
	return $self->archive2_file if $self->has_archive2_file;
	return $self->wav_file      if $self->has_wav_file;
	return $self->mp3_file      if $self->has_mp3_file;
	die "No audio file for @{[$self->identifier]} found";
}

method archive2_file_path {
	return $self->app->archive2_dir->child($self->identifier . '.flac');
}

method cmp($other, $swap?) {
	return 1 unless _INSTANCE $other, __PACKAGE__;

	for my $attr (@METADATA_ATTRS) {
		no warnings 'uninitialized';
		my $cmp = $self->$attr cmp $other->$attr;
		return $swap ? $cmp * -1 : $cmp if $cmp != 0;
	}

	return 0;
}

method from_txt($class: $app, $text, %attr) {
	my @s = split /\r?\n/, $text;
	%attr = (
		app => $app,
		identifier => $s[0],
		scripture_reading => $s[1],
		scripture_reading_might_be_focus => 1,
		title => $s[2],
		(speaker => $s[3])x!! $s[3],
		%attr,
	);

	if ($attr{title} =~ /([^:]+?): (.+)/) {
		$attr{title} = $2;
		$attr{series} = $1;
	}

	return $class->new(%attr);
}

method has_mp3_file {
	exists $self->{mp3_file} || -f $self->mp3_file_path || $self->has_wav_file;
}

method has_wav_file {
	exists $self->{wav_file} || -f $self->wav_file_path || $self->has_archive2_file;
}

method has_archive2_file {
	exists $self->{archive2_file} || -f $self->archive2_file_path;
}

method mp3_file_path {
	my $app = $self->app;
	my $archived = $app->archived_mp3_dir->child($self->identifier . '.mp3');
	-f $archived ? $archived : $app->base_dir->child($app->mp3_prefix . $self->identifier . '.mp3');
}

method to_hash {
	+{ map { ($_ => $self->$_.'')x!! $self->$_ } @METADATA_ATTRS };
}

method to_yaml {
	require YAML;
	YAML::Dump($self->to_hash)
}

method upload(:$always, :$file_mode = 'upload') {
	my $app = $self->app;
	my $existing = $app->api->get('sermon/' . $self->identifier)->andand->{data} // {};
	my %set;

	if (!$existing->{audio_url} || $always) {
		if ($file_mode eq 'upload') {
			$set{audio} = {
				file     => $self->mp3_file->stringify,
				filename => $app->mp3_prefix . $self->identifier . '.mp3',
			};
		}
		elsif ($file_mode eq 'existing') {
			$set{audio} = 'file://'
				. $app->api_sermon_files_dir->file($app->mp3_prefix . $self->identifier . '.mp3');
		}
		elsif ($file_mode eq 'remote') {
			$set{audio} = $app->audio_url_base . '/' . $self->identifier . '.mp3';
		}
		else {
			die "Invalid file mode: $file_mode";
		}
	}

	for (@METADATA_ATTRS) {
		$set{$_} = $self->$_ if $existing->{$_} ne $self->$_ or $always;
	}

	return unless %set;

	$set{identifier} = $self->identifier;
	if (keys %$existing) {
		$app->api->patch('sermon/' . $self->identifier, form => \%set);
	}
	else {
		$app->api->post('sermon', form => \%set);
	}

	return;
}

method wav_file_path {
	return $self->app->base_dir->child($self->identifier . '.wav');
}

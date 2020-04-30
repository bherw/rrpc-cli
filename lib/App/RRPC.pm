package App::RRPC;

use Kavorka;
use MooseX::App qw(Color ConfigHome);
use MooseX::AttributeShortcuts;
use MooseX::LazyRequire;
use MooX::RelatedClasses;
use Types::Path::Tiny qw(Path);
use Path::Tiny;
use Type::Utils qw(class_type);
use Types::Standard qw(Str);
use namespace::autoclean -except => 'new_with_command';
use v5.14;

app_namespace 'App::RRPC::Command';

related_class [qw(Sermons)];
related_class {API => 'api'};
related_class { '+Mojo::Asset::File' => 'asset'};
related_class 'Pg', namespace => 'Mojo';

has 'api',
	is => 'lazy',
	builder => method {
		$self->api_class->new(
			api_base => $self->api_base,
			access_key => $self->api_key,
			inactivity_timeout => 0,
		);
	};

has 'local_timezone',
	is => 'lazy',
	isa => class_type('DateTime::TimeZone'),
	builder => method {
		require DateTime::TimeZone;
		DateTime::TimeZone->new(name => 'local');
	};

has 'pg',
	is      => 'lazy',
	builder => method {
		my $pg = $self->pg_class->new($self->db_connection_string);
		$pg->auto_migrate(1)->migrations->name('rrpc_cli')->from_data;
		$pg;
	};

has 'sermons',
	is      => 'lazy',
	builder => method {
		$self->sermons_class->new(app => $self);
	};

option 'am_sermon_time', is => 'ro', isa => Str, required => 1;
option 'api_base', is => 'ro', lazy_required => 1;
option 'api_key', is => 'ro', lazy_required => 1;
option 'api_sermon_files_dir', is => 'rw', isa           => Path, coerce => 1, lazy_required => 1;
option 'archive_dir',
	is      => 'lazy',
	isa     => Path,
	coerce  => 1,
	default => method { $self->base_dir->child('archive') };
option 'audio_peaks_resolution', is => 'ro', isa => 'Int', default => 4096;
option 'audio_url_base', is => 'ro', lazy_required => 1;
option 'base_dir', is => 'ro', isa => Path, coerce => 1, default => sub { path('.') };
option 'db_connection_string', is => 'ro', default => 'postgresql:///rrpc_cli';
option 'default_speaker', is => 'ro', lazy_required => 1;
option 'mp3_album', is => 'ro', lazy_required => 1;
option 'mp3_prefix', is => 'ro', default => '';
option 'mp3_quality', is => 'ro', default => 5;
option 'pm_sermon_time', is => 'ro', isa => Str, required => 1;

method archive0_dir { $self->archive_dir->child('0-raw') }
method archive1_dir { $self->archive_dir->child('1-cut') }
method archive2_dir { $self->archive_dir->child('2-final') }
method archived_mp3_dir { $self->archive_dir->child('mp3') }

method upload_sermons(\@sermons, :$overwrite_audio = 0, :$create_speaker = 0, :$create_series = 0) {
	my $api = $self->api;

	# Validate
	$self->_assert_mp3_available(@sermons);
	for my $sermon (@sermons) {
		my $speaker = $api->get_speaker_by_name($sermon->speaker);
		unless ($speaker) {
			if ($create_speaker) {
				$api->create_speaker(name => $sermon->speaker);
			}
			else {
				say "No such speaker: @{[$sermon->speaker]} for @{[$sermon->identifier]}";
				say "To create the speaker, rerun with --create_speaker";
				exit 1;
			}
		}

		if (defined $sermon->series) {
			my $series = $api->get_series_by_name_and_speaker_id($sermon->series, $speaker->{id});
			unless ($series) {
				if ($create_series) {
					$api->create_series(name => $sermon->series, speaker_id => $speaker->{id});
				}
				else {
					say "No such series by @{[$sermon->speaker]} named '@{[$sermon->series]}' for @{[$sermon->identifier]}";
					say "To create the series, rerun with --create_series";
					exit 1;
				}
			}
		}
	}

	for my $sermon (@sermons) {
		$api->set_sermon($sermon, overwrite_audio => $overwrite_audio);
	}
}

method _assert_mp3_available(@sermons) {
	for my $sermon (@sermons) {
		unless ($sermon->has_mp3_file) {
			say 'No source file found for ' . $sermon->identifier;
			exit 1;
		}
	}
}

1;

__DATA__
@@ rrpc_cli
-- 1 up
create table if not exists sermons (
	id                               bigserial primary key,
	identifier                       text unique not null,
	recorded_at                      timestamp not null,
	series                           text,
	scripture_focus                  text,
	scripture_reading                text not null,
	scripture_reading_might_be_focus bool not null,
	speaker                          text not null,
	title                            text
);

-- 1 down
drop table if exists sermons;

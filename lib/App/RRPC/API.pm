package App::RRPC::API;

use App::RRPC::API::Upload;
use Mojo::Base 'Mojo::UserAgent';
use MooX::RelatedClasses;
use Scalar::Util qw(blessed);
use Kavorka;

my @SERMON_SCALAR_ATTRS = qw(
	identifier recorded_at scripture_focus scripture_reading
	scripture_reading_might_be_focus title
);

has 'api_base';
has 'access_key';
has 'ca' => sub { \undef }; # Enable CA cert checking -- Mojo disables it by default

for my $method (qw(get patch post put delete)) {
	no strict 'refs';
	*$method = sub {
		my $self = shift;
		my $url  = Mojo::URL->new($self->api_base . '/' . shift);
		if ($self->access_key) {
			$url->query->param(access_key => $self->access_key);
		}
		return $self->${ \"SUPER::$method" }($url, @_)->result;
	}
}

method create_series(Str :$name, Int :$speaker_id) {
	my $res = $self->post('series', json => {
		series => {
			name       => $name,
			speaker_id => $speaker_id,
		}
	});

	$self->_throw_error("Error creating series '$name'", $res) unless $res->code == 201;

	$self->_load_series;
	$self->{series}{by_name_and_speaker_id}{$name}{$speaker_id} = $res->json->{data};
}

method create_speaker(Str :$name) {
	my $res = $self->post('speakers', json => { speaker => { name => $name } });

	$self->_throw_error("Error creating speaker '$name'", $res) unless $res->code == 201;

	$self->_load_speakers;
	$self->{speaker}{by_name}{$name} = $res->json->{data};
}

method get_series_by_name_and_speaker_id(Str $name, Int $speaker_id) {
	$self->_load_series;
	$self->{series}{by_name_and_speaker_id}{$name}{$speaker_id}
}

method get_sermon(Str $id) {
	my $res = $self->get('sermons/' . $id);
	return if $res->code == 404;
	$self->_throw_error("Error getting sermon: $id", $res) unless $res->code == 200;
	return $res->json->{data};
}

method get_speaker_by_name(Str $name) {
	$self->_load_speakers;
	$self->{speakers}{by_name}{$name}
}

sub sermon_class {
	require App::RRPC::Sermon;
	'App::RRPC::Sermon'
}

method set_sermon(App::RRPC::Sermon $sermon, :$overwrite_audio = 0) {
	my $existing = $self->get_sermon($sermon->identifier);
	my %set;

	for my $attr (@SERMON_SCALAR_ATTRS) {
		if (!defined $existing || $sermon->$attr ne $existing->{$attr}) {
			$set{$attr} = $sermon->$attr;
		}
	}

	my $speaker = $self->get_speaker_by_name($sermon->speaker)
		or die "No speaker by name: @{[$sermon->speaker]}";
	if (!defined $existing || $speaker->{id} != $existing->{speaker_id}) {
		$set{speaker_id} = $speaker->{id};
	}

	if (defined $sermon->series) {
		my $series = $self->get_series_by_name_and_speaker_id($sermon->series, $speaker->{id})
			or die "No series by @{[$speaker->name]} with name @{[$sermon->series]}";
		if (!defined $existing || $existing->{series_id} != $sermon->series_id) {
			$set{series_id} = $series->{id};
		}
	}
	elsif (defined $existing && $existing->{series_id}) {
		$set{series_id} = undef;
	}

	if (!defined $existing || $overwrite_audio) {
		$set{audio} = App::RRPC::API::Upload->new(
			file     => $sermon->mp3_file->stringify,
			filename => $sermon->mp3_file_name,
		);
	}

	return unless %set;
	if (defined $existing) {
		my $res = $self->patch('sermons/' . $sermon->identifier, _form({sermon => \%set}));
		$self->_throw_error("Error patching sermon @{[$sermon->identifier]}", $res) unless $res->code == 200;
	}
	else {
		my $res = $self->post('sermons', _form({sermon => \%set}));
		$self->_throw_error("Error creating sermon @{[$sermon->identifier]}", $res) unless $res->code == 201;
	}

	return;
}

method delete_sermon($sermon) {
	my $id = ref $sermon ? $sermon->{identifier} : $sermon;
	my $res = $self->get('sermons/' . $id);
	$self->_throw_error('Error deleting sermon', $res) unless $res->code == 200;
	return 1;
}

fun _form($data) {
	(form => { _form_rec($data) })
}

fun _form_rec($data, $name = '') {
	map {
		if (blessed $data->{$_}) {
			if ($data->{$_}->isa('App::RRPC::API::Upload')) {
				(_form_name($name, $_) => { %{ $data->{$_} } })
			}
			else {
				(_form_name($name, $_) => $data->{$_}.'')
			}
		}
		elsif (ref $data->{$_} eq 'HASH') {
			_form_rec($data->{$_}, _form_name($name, $_))
		}
		else {
			(_form_name($name, $_) => $data->{$_})
		}
	} keys %$data
}

fun _form_name($base, $key) {
	$base ? $base . '[' . $key . ']' : $key;
}

method _load_series {
	return if defined $self->{series};

	my $res = $self->get('series');
	$self->_throw_error('Error loading series:', $res) unless $res->code == 200;

	for my $series (@{ $res->json->{data}{results} }) {
		$self->{series}{by_name_and_speaker_id}{ $series->{name} }{ $series->{speaker_id} }
			= $series;
	}
}

method _load_speakers {
	return if defined $self->{speakers};

	my $res = $self->get('speakers');
	$self->_throw_error('Error loading speakers:', $res) unless $res->code == 200;

	for my $speaker (@{ $res->json->{data}{results} }) {
		$self->{speakers}{by_name}{ $speaker->{name} } = $speaker;
	}
}

method _throw_error($message, $res) {
	if (!$res->json) {
		die "$message:\n". $res->code . ' ' . $res->message . "\n". $res->body;	
	}
	die "$message:\n"
		. $res->code . ' ' . $res->message . "\n"
		. join("\n", @{$res->json->{errors} || []});
}

1;

package App::RRPC::Command::upload;

use Kavorka;
use MooseX::App::Command;
use v5.14;

extends 'App::RRPC';

option 'all',       is => 'rw', isa => 'Bool';
option 'always',    is => 'ro', isa => 'Bool', default => 0;
option 'file_mode', is => 'ro', isa => 'Str',  default => 'upload';

method run {
	my $sermons;
	if ($self->all) {
		$sermons = $self->sermons->load_all(order => 'recorded_at');
	}
	else {
		$sermons = $self->load_metadata;
	}

	# Validate source files.
	for my $sermon (@$sermons) {
		unless ($sermon->has_mp3_file) {
			say 'No source file found for ' . $sermon->identifier;
			exit 1;
		}
	}

	for my $sermon (@$sermons) {
		$sermon->upload(always => $self->always, file_mode => $self->file_mode);
	}
}

1;

package App::RRPC::Command::upload;

use Kavorka;
use MooseX::App::Command;
use v5.14;

extends 'App::RRPC';

option 'only',
	is => 'ro',
	isa => 'ArrayRef[Str]';

option 'metadata_only',
	is => 'ro',
	isa => 'Bool',
	default => 0;

method run {
	my $sermons = $self->load_metadata;
	my $metadata_only = $self->metadata_only;

	# Validate source files.
	for my $sermon (@$sermons) {
		unless ($metadata_only || $sermon->has_wav_file) {
			say 'No source file found for ' . $sermon->date;
			exit 1;
		}
	}

	for my $sermon (@$sermons) {
		$sermon->upload(upload_file => !$metadata_only);
	}
}

1;

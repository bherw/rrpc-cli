package App::RRPC::Command::encode;

use Kavorka;
use MooseX::App::Command;
use Path::Class;
use v5.14;

extends 'App::RRPC';

option 'output_dir',
	is => 'ro',
	isa => 'Str',
	default => sub { '.' },
	cmd_flag => 'output-dir';

method run {
	my $sermons = $self->load_metadata;
	my $outdir  = dir($self->output_dir);

	# Validate source files.
	for my $sermon (@$sermons) {
		unless ($sermon->has_wav_file) {
			say 'No source file found for ' . $_->date;
			exit 1;
		}
	}

	for my $sermon (@$sermons) {
		$sermon->mp3_file->move_to($outdir->file($self->mp3_prefix . $sermon->identifier . '.mp3'));
	}
}

1;

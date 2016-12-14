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
	require Parallel::ForkManager;
	require Sys::CPU;

	my $outdir  = dir($self->output_dir);

	# Validate source files.
	for my $sermon (@$sermons) {
		unless ($sermon->has_mp3_file) {
			say 'No source file found for ' . $sermon->identifier;
			exit 1;
		}
	}

	my $pm = Parallel::ForkManager->new(Sys::CPU::cpu_count());
	for my $sermon (@$sermons) {
		my $pid = $pm->start and next;

		my $mp3_file = $sermon->mp3_file;
		my $target   = $outdir->file($self->mp3_prefix . $sermon->identifier . '.mp3');
		if ($mp3_file ne $target) {
			my $action = $mp3_file->isa('App::RRPC::TempFile') ? 'move_to' : 'copy_to';
			$mp3_file->$action($target);
		}

		$pm->finish;
	}
	$pm->wait_all_children;
}

1;

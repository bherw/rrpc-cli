package App::RRPC::Command::archive0;

use v5.14;
use MooseX::App::Command;
use Path::Tiny;

extends 'App::RRPC';

sub run {
	my ($self) = @_;
	my $archive0_dir = $self->archive0_dir;
	my @files = path('.')->children(qr/\.(?:wav|flac)\z/);
	for my $file (@files) {
		if ($file =~ /wav\z/) {
			system qw(flac -8), $file, '-o', $archive0_dir->file(($file =~ s/\.wav\z//r) . '.flac');
		}
		else {
			print "cp $file " . $archive0_dir->file(($file =~ s/\.wav\z//r) . '.flac') . "\n";
			$file->copy($archive0_dir->file(($file =~ s/\.wav\z//r)));
		}
	}
}

1;

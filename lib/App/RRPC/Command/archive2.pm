package App::RRPC::Command::archive2;

use MooseX::App::Command;

sub run {
	system "flac -8 --output-prefix=\"archive/2-final/\" *wav";
}

1;

package App::RRPC::Command::archive1;

use MooseX::App::Command;

sub run {
	system "flac -8 --output-prefix=\"archive/1-cut/\" *wav";
}

1;

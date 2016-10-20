package App::RRPC::Command::archive0;

use MooseX::App::Command;

sub run {
	system "flac -8 --output-prefix=\"archive/0-raw/\" *wav";
}

1;

package App::RRPC::Util;

use common::sense;
use IPC::Run;

use Sub::Exporter::Progressive -setup => {
	exports => [qw(audiowaveform flac lame)],
};

sub audiowaveform {
	IPC::Run::run ['audiowaveform', @_];
}

sub flac {
	IPC::Run::run ['flac', @_];
}

sub lame {
	IPC::Run::run ['lame', @_];
}

1;

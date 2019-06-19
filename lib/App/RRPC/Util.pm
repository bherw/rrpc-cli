package App::RRPC::Util;

use common::sense;

use Sub::Exporter::Progressive -setup => {
	exports => [qw(audiowaveform flac lame)],
};

sub audiowaveform {
	require IPC::Run;
	IPC::Run::run(['audiowaveform', @_]);
}

sub flac {
	require IPC::Run;
	IPC::Run::run(['flac', @_]);
}

sub lame {
	require IPC::Run;
	IPC::Run::run(['lame', @_]);
}

1;

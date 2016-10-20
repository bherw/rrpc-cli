package App::RRPC::Command::info;

use Kavorka;
use MooseX::App::Command;
use v5.14;

extends 'App::RRPC';

option 'all', is => 'rw', isa => 'Bool';

method run {
	my $sermons;

	if ($self->all) {
		$sermons = $self->sermons->load_all(order => 'recorded_at');
	}
	else {
		$sermons = $self->load_metadata;
	}

	say $self->sermons->to_yaml($sermons);
}

1;

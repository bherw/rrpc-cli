package App::RRPC::Command::info;

use Kavorka;
use MooseX::App::Command;
use v5.14;

extends 'App::RRPC';
with 'App::RRPC::Role::SermonSelector';

method run {
	say $self->sermons->to_yaml($self->selected_sermons);
}

1;

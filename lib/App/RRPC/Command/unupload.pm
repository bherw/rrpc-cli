package App::RRPC::Command::unupload;

use Kavorka;
use MooseX::App::Command;
use Scalar::Andand;
use v5.14;

extends 'App::RRPC';
with 'App::RRPC::Role::SermonSelector';

method run {
    my $sermons = $self->selected_sermons;
    my $api = $self->api;

    say "No sermons selected" unless @$sermons;

    for my $sermon (@$sermons) {
        say $sermon->identifier;
        my $existing = $api->get_sermon($sermon->identifier);

        if ($existing) {
            say "DELETE " . $sermon->identifier;
            $api->delete_sermon($sermon->identifier);
        }
        else {
            say "No such sermon on remote: " . $sermon->identifier;
        }
    }
}

1;

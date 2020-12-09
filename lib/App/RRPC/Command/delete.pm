package App::RRPC::Command::delete;

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
        say "Purging " . $sermon->identifier;

        # Delete archive files
        my $file = $sermon->identifier . ".flac";
        my $path = $self->archive0_dir->child($file);
        say "rm $path";
        $path->remove;

        $path = $self->archive1_dir->child($file);
        say "rm $path";
        $path->remove;

        $path = $self->archive2_dir->child($file);
        say "rm $path";
        $path->remove;

        # Delete from remote
        my $existing = $api->get_sermon($sermon->identifier);
        if ($existing) {
            say "DELETE " . $sermon->identifier;
            $api->delete('sermons/' . $sermon->identifier);
        }
        else {
            say "No such sermon on remote: " . $sermon->identifier;
        }

        # Delete record from db
        $self->pg->db->delete('sermons', { identifier => $sermon->identifier });
    }

}

1;

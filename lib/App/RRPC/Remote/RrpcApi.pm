package App::RRPC::Remote::RrpcApi;

use v5.14;
use Kavorka;
use Moose;
use MooseX::AttributeShortcuts;
use MooseX::RelatedClasses;

related_class { API => 'api' }, namespace => 'App::RRPC';

has 'api',
    is      => 'lazy',
    builder => method {
        $self->api_class->new(api_base => $self->api_base, access_key => $self->api_key, inactivity_timeout => 0);
    };

has 'api_base',
    is       => 'ro',
    required => 1;

has 'api_key',
    is       => 'ro',
    required => 1;



method upload_sermons(\@sermons, :$overwrite_audio = 0, :$create_speaker = 0, :$create_series = 0) {
    print 'Validating sermons for upload to RRPC Sermons... ';

    my $api = $self->api;

    # Validate
    my ($unknown_speakers, $unknown_series);
    for my $sermon (@sermons) {
        my $speaker = $api->get_speaker_by_name($sermon->speaker);
        unless ($speaker) {
            if ($create_speaker) {
                $api->create_speaker(name => $sermon->speaker);
            }
            else {
                say;
                say "No such speaker: @{[ $sermon->speaker ]} for @{[ $sermon->identifier ]}";
                say "To create the speaker on the RRPC sermons site, rerun with --create_speaker";
                $unknown_speakers++;
            }
        }

        if (defined $sermon->series) {
            my $series = $api->get_series_by_name_and_speaker_id($sermon->series, $speaker->{id});
            unless ($series) {
                if ($create_series) {
                    $api->create_series(name => $sermon->series, speaker_id => $speaker->{id});
                }
                else {
                    say;
                    say "No such series by @{[ $sermon->speaker ]} named '@{[ $sermon->series ]}' for @{[ $sermon->identifier ]}";
                    say "To create the series on the RRPC sermons site, rerun with --create_series";
                    $unknown_series++;
                }
            }
        }
    }
    return if $unknown_speakers || $unknown_series;
    say 'OK';

    for my $sermon (sort { $a->identifier cmp $b->identifier } @sermons) {
        print 'Updating ' . $sermon->identifier . ' on RRPC Sermons... ';
        $api->set_sermon($sermon, overwrite_audio => $overwrite_audio);
        say 'done.';
    }
}

1;
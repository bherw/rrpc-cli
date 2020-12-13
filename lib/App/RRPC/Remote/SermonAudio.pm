package App::RRPC::Remote::SermonAudio;

use v5.14;
use Kavorka;
use List::Util qw(uniq);
use Moose;
use MooseX::AttributeShortcuts;
use MooseX::RelatedClasses;
use Net::SermonAudio::Util qw(await_get);
use Types::Standard qw(HashRef Str);

use constant MEDIA_PROCESSING_POLL_INTERVAL => 15;

related_class { 'Net::SermonAudio::API::Broadcaster' => 'sermon_audio' }, namespace => undef;

has 'api',
    is      => 'lazy',
    builder => method {
        my $api_key = $self->api_key or die "sermon audio api key is required";
        $self->broadcaster_id or die "sermon audio broadcaster id is required";
        $self->sermon_audio_class->new(api_key => $api_key)
    };

has 'api_key',
    is       => 'ro',
    isa      => Str,
    required => 1;

has 'app',
    is       => 'ro',
    required => 1,
    weak_ref => 1;

has 'broadcaster_id',
    is       => 'ro',
    isa      => Str,
    required => 1;

has 'language_code',
    is       => 'ro',
    isa      => Str,
    default  => 'en',
    required => 1;

has 'speaker_name_map',
    is      => 'ro',
    isa     => HashRef [ Str ],
    default => sub { {} };


method upload_sermons(\@sermons, :$overwrite_audio = 0, :$create_speaker = 0, :$create_series = 0) {
    my @publish_queue;
    my $sermons_on_sa = $self->_sermons_on_sa(\@sermons);
    my $sa            = $self->api;

    for my $sermon (sort { $a->identifier cmp $b->identifier } @sermons) {
        my $sa_speaker = $self->speaker_name_map->{$sermon->speaker} // $sermon->speaker;
        my $remote     = $sermons_on_sa->{$sermon->identifier};
        if ($remote && !(
            $remote->full_title eq $sermon->title
                && ($remote->subtitle // '') eq ($sermon->series // '')
                && $remote->speaker->display_name eq $sa_speaker
                && $remote->bible_text eq $sermon->scripture)) {

            say "non-matching title" unless $remote->full_title eq $sermon->title;
            say "non-matching series" unless $remote->subtitle // '' eq $sermon->series // '';
            say 'non-matching speaker' unless $remote->speaker->display_name eq $sa_speaker;
            say "non-matching scripture: @{[ $remote->bible_text ]} != @{[ $sermon->scripture ]}" unless $remote->bible_text eq $sermon->scripture;

            print "Updating " . $sermon->identifier . ' on SermonAudio...';
            $remote = await_get $sa->update_sermon(
                $remote,
                accept_copyright => 1,
                full_title       => $sermon->title,
                display_title    => '',
                speaker_name     => $sa_speaker,
                subtitle         => $sermon->series,
                bible_text       => $sermon->scripture,
                news_in_focus    => 0,
            );
            say ' done.';
        }
        elsif (!$remote) {
            print 'Adding ' . $sermon->identifier . ' to SermonAudio...';
            $remote = await_get $sa->create_sermon(
                accept_copyright => 1,
                bible_text       => $sermon->scripture,
                event_type       => 'Sunday - ' . $sermon->identifier =~ s/\d+-\d+-\d+//r,
                full_title       => $sermon->title,
                language_code    => $self->language_code,
                preach_date      => Date::Tiny->new(
                    year  => $sermon->recorded_at->year,
                    month => $sermon->recorded_at->month,
                    day   => $sermon->recorded_at->day,
                ),
                speaker_name     => $sa_speaker,
                subtitle         => $sermon->series,
            );
            say ' done.';
        }

        if ($remote && !$remote->publish_timestamp) {
            say "Adding @{[ $sermon->identifier ]} to publish queue.";
            push @publish_queue, $remote;
        }

        if (!@{$remote->media->audio} || $overwrite_audio) {
            print 'Uploading mp3 for ' . $sermon->identifier . '...';
            await_get $sa->upload_audio($remote, $sermon->mp3_file);
            say ' done.';
        }
    }

    # Do this a bit later to give SA some time to process the uploaded media.
    for my $sermon (@publish_queue) {
        print 'Publishing ' . _sa_sermon_identifier($sermon) . '...';

        # Wait for media processing
        my $notified_user_about_reason_for_wait;
        while (1) {
            $sermon = await_get $sa->get_sermon($sermon);
            last if @{$sermon->media->audio};
            print ' waiting for media processing to finish...' unless $notified_user_about_reason_for_wait++;
            sleep MEDIA_PROCESSING_POLL_INTERVAL;
        }

        await_get $sa->publish_sermon($sermon);
        say ' done.';
    }
}

method validate_upload_sermons(\@sermons, :$overwrite_audio = 0, :$create_speaker = 0, :$create_series = 0) {
    print 'Validating sermons for upload to SermonAudio...';

    my $sa      = $self->api;
    my $unknown = 0;
    if (!$create_speaker) {
        for my $speaker (uniq map { $_->speaker } @sermons) {
            my $sa_speaker = $self->speaker_name_map->{$speaker} // $speaker;

            if (!await_get($sa->speaker_exists($sa_speaker))) {
                say '';
                say "No such speaker '$speaker' exists on SermonAudio.";
                say "Please confirm that no similar speaker, for example 'Pastor $speaker' exists on SermonAudio.";
                say "If such a speaker does exist, add \"$speaker: Pastor $speaker\" to the sermon_audio_speaker_name_map: option in the config file located at " . $self->app->config;
                say "To create the speaker, rerun with --create_speaker";
                $unknown++;
            }
        }
    }

    if (!$create_series) {
        for my $series (uniq grep { defined } map { $_->series } @sermons) {
            if (!(await_get $sa->series_exists($self->broadcaster_id, $series))) {
                say '';
                say "No series called '$series' exists on SermonAudio. Check that the series name is not misspelled.";
                say "If this is a new series, rerun this command with --create_series to create the series on SermonAudio.";
                $unknown++;
            }
        }
    }

    return if $unknown;
    say ' OK';
    return 1;
}

method _sermons_on_sa(\@sermons) {
    # Get existing sermons for this time window
    my @recording_times = sort map { $_->recorded_at } @sermons;
    my $first_preached  = $recording_times[0];
    my $last_preached   = $recording_times[-1];
    my $sermon_set      = await_get $self->api->list_sermons_between($first_preached, $last_preached, include_drafts => 1);
    my %sermons_on_site = map { (_sa_sermon_identifier($_) => $_) } @{$sermon_set->results};
    return \%sermons_on_site;
}

fun _sa_sermon_identifier($sermon) {
    $sermon->preach_date->ymd . ($sermon->event_type =~ s/Sunday - //r)
}

1;

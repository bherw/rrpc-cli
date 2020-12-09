package App::RRPC;

use List::Util qw(uniq);
use Kavorka;
use MooseX::App qw(Color ConfigHome);
use MooseX::AttributeShortcuts;
use MooseX::LazyRequire;
use MooX::RelatedClasses;
use Net::SermonAudio::Util qw(await_get);
use Types::Path::Tiny qw(Path);
use Path::Tiny;
use Type::Utils qw(class_type);
use Types::Standard qw(HashRef Str);
use namespace::autoclean -except => 'new_with_command';
use v5.14;

use constant MEDIA_PROCESSING_POLL_INTERVAL => 15;

app_namespace 'App::RRPC::Command';

related_class [ qw(Sermons) ];
related_class { API => 'api' };
related_class { '+Mojo::Asset::File' => 'asset', '+Net::SermonAudio::API::Broadcaster' => 'sermon_audio' };
related_class 'Pg', namespace => 'Mojo';

has 'api',
	is      => 'lazy',
	builder => method {
		$self->api_class->new(api_base => $self->api_base, access_key => $self->api_key, inactivity_timeout => 0);
	};

has 'local_timezone',
	is      => 'lazy',
	isa     => class_type('DateTime::TimeZone'),
	builder => method {
		require DateTime::TimeZone;
		DateTime::TimeZone->new(name => 'local');
	};

has 'pg',
	is      => 'lazy',
	builder => method {
		my $pg = $self->pg_class->new($self->db_connection_string);
		$pg->auto_migrate(1)->migrations->name('rrpc_cli')->from_data;
		$pg;
	};

has 'sermon_audio',
	is      => 'lazy',
	builder => method {
		my $api_key = $self->sermon_audio_api_key or die "sermon audio api key is required";
		$self->sermon_audio_broadcaster_id or die "sermon audio broadcaster id is required";
		$self->sermon_audio_class->new(api_key => $api_key)
	};

has 'sermons',
	is      => 'lazy',
	builder => method {
		$self->sermons_class->new(app => $self);
	};

option 'am_sermon_time', is => 'ro', isa => Str, required => 1;
option 'api_base', is => 'ro', lazy_required => 1;
option 'api_key', is => 'ro', lazy_required => 1;
option 'api_sermon_files_dir', is => 'rw', isa           => Path, coerce => 1, lazy_required => 1;
option 'archive_dir',
	is      => 'lazy',
	isa     => Path,
	coerce  => 1,
	default => method { $self->base_dir->child('archive') };
option 'audio_peaks_resolution', is => 'ro', isa => 'Int', default => 4096;
option 'audio_url_base', is => 'ro', lazy_required => 1;
option 'base_dir', is => 'ro', isa => Path, coerce => 1, default => sub { path('.') };
option 'db_connection_string', is => 'ro', default => 'postgresql:///rrpc_cli';
option 'default_speaker', is => 'ro', lazy_required => 1;
option 'mp3_album', is => 'ro', lazy_required => 1;
option 'mp3_prefix', is => 'ro', default => '';
option 'mp3_quality', is => 'ro', default => 5;
option 'sermon_audio_api_key', is => 'ro', isa => Str;
option 'sermon_audio_broadcaster_id', is => 'ro', isa => Str;
option 'sermon_audio_language_code', is => 'ro', isa => Str, default => 'en';
option 'sermon_audio_speaker_name_map', is => 'ro', isa => HashRef [ Str ], default => sub { {} };
option 'pm_sermon_time', is => 'ro', isa => Str, required => 1;

method archive0_dir { $self->archive_dir->child('0-raw') }
method archive1_dir { $self->archive_dir->child('1-cut') }
method archive2_dir { $self->archive_dir->child('2-final') }
method archived_mp3_dir { $self->archive_dir->child('mp3') }

method upload_sermons(@_) {
	if ($self->{api_key}) {
		$self->upload_sermons_rrpc_api(@_);
	}
	else {
		say 'RRPC API key not configured, not uploading to RRPC Sermons';
	}

	if ($self->{sermon_audio_api_key}) {
		$self->upload_sermons_sermonaudio(@_);
	}
	else {
		say "SermonAudio API key not configured, not uploading to SermonAudio.";
	}
}

method upload_sermons_rrpc_api(\@sermons, :$overwrite_audio = 0, :$create_speaker = 0, :$create_series = 0) {
	my $api = $self->api;

	# Validate
	$self->_assert_mp3_available(@sermons);
	my ($unknown_speakers, $unknown_series);
	for my $sermon (@sermons) {
		my $speaker = $api->get_speaker_by_name($sermon->speaker);
		unless ($speaker) {
			if ($create_speaker) {
				$api->create_speaker(name => $sermon->speaker);
			}
			else {
				say "No such speaker: @{ [ $sermon->speaker ] } for @{ [ $sermon->identifier ] }";
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
					say "No such series by @{ [ $sermon->speaker ] } named '@{ [ $sermon->series ] }' for @{ [ $sermon->identifier ] }";
					say "To create the series on the RRPC sermons site, rerun with --create_series";
					$unknown_series++;
				}
			}
		}
	}
	return if $unknown_speakers || $unknown_series;

	for my $sermon (sort { $a->identifier cmp $b->identifier } @sermons) {
		$api->set_sermon($sermon, overwrite_audio => $overwrite_audio);
	}
}

method upload_sermons_sermonaudio(\@sermons, :$overwrite_audio = 0, :$create_speaker = 0, :$create_series = 0) {
	my $sa = $self->sermon_audio;

	# Validate
	print 'Validating sermons for upload to SermonAudio...';
	$self->_assert_mp3_available(@sermons);
	my $unknown_speakers;
	for my $speaker (uniq map { $_->speaker } @sermons) {
		my $sa_speaker = $self->sermon_audio_speaker_name_map->{$speaker} // $speaker;

		if (!await_get($sa->speaker_exists($sa_speaker)) && !$create_speaker) {
			say '';
			say "No such speaker '$speaker' exists on SermonAudio.";
			say "Please confirm that no similar speaker, for example 'Pastor $speaker' exists on SermonAudio.";
			say "If such a speaker does exist, add \"$speaker: Pastor $speaker\" to the sermon_audio_speaker_name_map: option in the config file located at " . $self->config;
			say "To create the speaker, rerun with --create_speaker";
			$unknown_speakers++;
		}
	}

	my $unknown_series;
	for my $series (uniq grep { defined } map { $_->series } @sermons) {
		next if await_get $sa->series_exists($self->sermon_audio_broadcaster_id, $series);

		if (!$create_series) {
			say '';
			say "No series called '$series' exists on SermonAudio. Check that the series name is not misspelled.";
			say "If this is a new series, rerun this command with --create_series to create the series on SermonAudio.";
			$unknown_series++;
		}
	}
	return if $unknown_speakers || $unknown_series;
	say ' OK';

	# Get existing sermons for this time window
	my @recording_times = sort map { $_->recorded_at } @sermons;
	my $first_preached = $recording_times[0];
	my $last_preached = $recording_times[-1];
	my $sermon_set = await_get $sa->list_sermons_between($first_preached, $last_preached, include_drafts => 1);
	my %sermons_on_site = map { (_sa_sermon_identifier($_) => $_) } @{ $sermon_set->results };

	my @publish_queue;
	for my $sermon (sort { $a->identifier cmp $b->identifier } @sermons) {
		my $sa_speaker = $self->sermon_audio_speaker_name_map->{$sermon->speaker} // $sermon->speaker;
		my $remote = $sermons_on_site{$sermon->identifier};
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
				full_title       => $sermon->title,
				speaker_name     => $sa_speaker,
				preach_date      => Date::Tiny->new(
					year  => $sermon->recorded_at->year,
					month => $sermon->recorded_at->month,
					day   => $sermon->recorded_at->day,
				), event_type    => 'Sunday - ' . $sermon->identifier =~ s/\d+-\d+-\d+//r,
				subtitle         => $sermon->series,
				bible_text       => $sermon->scripture,
				language_code    => $self->sermon_audio_language_code,
			);
			say ' done.';
		}

		if ($remote && !$remote->publish_timestamp) {
			say "Adding @{ [ $sermon->identifier ] } to publish queue.";
			push @publish_queue, $remote;
		}

		if (!@{ $remote->media->audio } || $overwrite_audio) {
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
			last if @{ $sermon->media->audio };
			print ' waiting for media processing to finish...' unless $notified_user_about_reason_for_wait++;
			sleep MEDIA_PROCESSING_POLL_INTERVAL;
		}

		await_get $sa->publish_sermon($sermon);
		say ' done.';
	}
}

method _assert_mp3_available(@sermons) {
	for my $sermon (@sermons) {
		unless ($sermon->has_mp3_file) {
			say 'No source file found for ' . $sermon->identifier;
			exit 1;
		}
	}
}

fun _sa_sermon_identifier($sermon) {
	$sermon->preach_date->ymd . ($sermon->event_type =~ s/Sunday - //r)
}

1;

__DATA__
@@ rrpc_cli
-- 1 up
create table if not exists sermons (
	id                               bigserial primary key,
	identifier                       text unique not null,
	recorded_at                      timestamp not null,
	series                           text,
	scripture_focus                  text,
	scripture_reading                text not null,
	scripture_reading_might_be_focus bool not null,
	speaker                          text not null,
	title                            text
);

-- 1 down
drop table if exists sermons;

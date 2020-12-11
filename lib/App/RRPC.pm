package App::RRPC;

use Kavorka;
use MooseX::App qw(Color ConfigHome);
use MooseX::AttributeShortcuts;
use MooseX::LazyRequire;
use MooseX::RelatedClasses;
use Types::Path::Tiny qw(Path);
use Path::Tiny;
use Type::Utils qw(class_type);
use Types::Standard qw(HashRef Str);
use namespace::autoclean -except => 'new_with_command';
use v5.14;

app_namespace 'App::RRPC::Command';

related_class [ qw(Sermons) ];
related_class 'Pg', namespace => 'Mojo';

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

has 'sermons',
	is      => 'lazy',
	builder => method {
		$self->sermons_class->new(app => $self);
	};

option 'am_sermon_time', is => 'ro', isa => Str, required => 1;
option 'api_base', is => 'ro', lazy_required => 1;
option 'api_key', is => 'ro', lazy_required => 1;
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
    my @sermons = @{ $_[0] };
    $self->_assert_mp3_available(@sermons);

	if ($self->{api_key}) {
		require App::RRPC::Remote::RrpcApi;
		my $rrpc = App::RRPC::Remote::RrpcApi->new(api_base => $self->api_base, api_key => $self->api_key);
		$rrpc->upload_sermons(@_);
	}
	else {
		say 'RRPC API key not configured, not uploading to RRPC Sermons';
	}

	if ($self->{sermon_audio_api_key}) {
		require App::RRPC::Remote::SermonAudio;
		my $sa = App::RRPC::Remote::SermonAudio->new(
            api_key => $self->sermon_audio_api_key,
            broadcaster_id => $self->sermon_audio_broadcaster_id,
            language_code => $self->sermon_audio_language_code,
            speaker_name_map => $self->sermon_audio_speaker_name_map
        );
		$sa->upload_sermons(@_);
	}
	else {
		say "SermonAudio API key not configured, not uploading to SermonAudio.";
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

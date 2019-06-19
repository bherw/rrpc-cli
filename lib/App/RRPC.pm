package App::RRPC;

use Kavorka;
use MooseX::App qw(Color ConfigHome);
use MooseX::AttributeShortcuts;
use MooseX::LazyRequire;
use MooX::RelatedClasses;
use Types::Path::Tiny qw(Path);
use Path::Tiny;
use namespace::autoclean -except => 'new_with_command';
use v5.14;

app_namespace 'App::RRPC::Command';

related_class [qw(Sermons)];
related_class {API => 'api'};
related_class { '+Mojo::Asset::File' => 'asset'};
related_class 'Pg', namespace => 'Mojo';

has 'api',
	is => 'lazy',
	builder => method {
		$self->api_class->new(
			api_base => $self->api_base,
			access_key => $self->api_key,
			inactivity_timeout => 0,
		);
	};

has 'pg',
	is => 'lazy',
	builder => method {
		my $pg = $self->pg_class->new($self->db_connection_string);
		$pg->auto_migrate(1)->migrations->name('rrpc_cli')->from_data;
		$pg;
	};

has 'sermons',
	is => 'lazy',
	builder => method {
		$self->sermons_class->new(app => $self);
	};

option 'api_base',             is => 'ro', lazy_required => 1;
option 'api_key',              is => 'ro', lazy_required => 1;
option 'api_sermon_files_dir', is => 'rw', isa           => Path, coerce => 1, lazy_required => 1;
option 'archive_dir',
	is      => 'lazy',
	isa     => Path,
	coerce  => 1,
	default => method { $self->base_dir->child('archive') };
option 'audio_peaks_resolution', is => 'ro', isa => 'Int', default => 4096;
option 'audio_url_base',       is => 'ro', lazy_required => 1;
option 'base_dir',             is => 'ro', isa           => Path, coerce => 1, default => sub { path('.') };
option 'db_connection_string', is => 'ro', default       => 'postgresql:///rrpc_cli';
option 'default_speaker',      is => 'ro', lazy_required => 1;
option 'mp3_album',            is => 'ro', lazy_required => 1;
option 'mp3_prefix',           is => 'ro', default       => '';
option 'mp3_quality',          is => 'ro', default       => 5;

method archive0_dir { $self->archive_dir->child('0-raw') }
method archive1_dir { $self->archive_dir->child('1-cut') }
method archive2_dir { $self->archive_dir->child('2-final') }
method archived_mp3_dir { $self->archive_dir->child('mp3') }

method upload_sermons(\@sermons, :$upload_files = 1) {
	if ($upload_files) {
		# Make sure the source files exist first.
		$_->mp3_file for @sermons;
	}

	$_->upload($upload_files) for @sermons;
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

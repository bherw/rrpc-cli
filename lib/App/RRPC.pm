package App::RRPC;

use v5.16;
use MooseX::App qw(Color ConfigHome);
use Kavorka;
use MooseX::AttributeShortcuts;
use MooseX::RelatedClasses;
use MooseX::Types::Path::Class qw(Dir);
use Path::Class;
use namespace::autoclean -except => 'new_with_command';

app_namespace 'App::RRPC::Command';

related_class [qw(Sermons)];
related_class { 'API' => 'api' };
related_class { 'File' => 'asset'}, namespace => 'Mojo::Asset';
related_class 'Pg', namespace => 'Mojo';

has 'api',
	is => 'lazy',
	builder => method {
		$self->api_class->new(api_base => $self->api_base, access_key => $self->api_key);
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

option 'api_base', is => 'ro', default => 'http://localhost:3000';
option 'api_key', is => 'ro';
option 'archive_dir', is => 'lazy', isa => Dir, coerce => 1, default => method { $self->base_dir->subdir('archive') };
option 'audio_peaks_resolution', is => 'ro', isa => 'Int', default => 4096;
option 'audio_url_base', is => 'ro', default => 'http://sermons.russellrpc.org/audio/mp3/';
option 'base_dir', is => 'ro', isa => Dir, coerce => 1, default => sub { dir };
option 'default_speaker', is => 'ro', default => 'Matt Kingswood';
option 'db_connection_string', is => 'ro', default => 'postgresql:///rrpc_cli';
option 'mp3_album', is => 'ro', default => 'Russell RPC';
option 'mp3_prefix', is => 'ro', default => 'rrpc-';
option 'mp3_quality', is => 'ro', default => 5;

method archive2_dir { $self->archive_dir->subdir('2-final') }
method archived_mp3_dir { $self->archive_dir->subdir('mp3') }

method load_metadata(ArrayRef $args?) {
	$args //= $self->extra_argv;
	my @sermons;

	if (!@$args) {
		my @identifiers;
		for (dir->children) {
			if ($_->basename =~ /^(\d{4}-\d\d-\d\d)\.\w+$/) {
				push @identifiers, $1;
			}
		}

		for (@identifiers) {
			push @sermons, $self->sermons->load($_)
				or say "no metadata found for $_, did you forget to import it?" and exit 1;
		}
	}
	else {
		for (@$args) {
			if (-f $_) {
				push @sermons, @{ $self->sermons->load_files($_) };
			}
			else {
				push @sermons, $self->sermons->load($_)
					or say "no metadata found for $_, did you forget to import it?" and exit 1;
			}
		}
	}

	say "No sermons specified." and exit 1 unless @sermons;
	\@sermons;
}

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

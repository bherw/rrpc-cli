package App::RRPC::Sermons;

use Encode qw(decode_utf8);
use Kavorka;
use Moo;
use MooX::RelatedClasses;
use namespace::autoclean;
use Type::Utils qw(class_type);
use Types::Path::Tiny qw(Path);
use YAML;

related_class 'Sermon', namespace => 'App::RRPC';

has 'app', is => 'ro', isa => class_type('App::RRPC'), required => 1, weak_ref => 1;
has 'pg',  is => 'rw', isa => class_type('Mojo::Pg'),  required => 1, default  => sub { shift->app->pg };

method load(Int $id) {
	return $self->where('id = ?', $id);
}

method load_all(Maybe[Str] :$order?) {
	$order = 'order by ' . $order if $order;
	return $self->_build($self->pg->db->query("select * from sermons $order"));
}

method load_by_identifier(Str $id) {
	return $self->where('identifier = ?', $id)->[0];
}

method load_files(\@files) {
	[map { $self->_load_file($_) } @files];
}

method save(App::RRPC::Sermon $sermon) {
	return $sermon->id($self->pg->db->query('
		insert into sermons (identifier, recorded_at, series, scripture_focus, scripture_reading,
			scripture_reading_might_be_focus, speaker, title)
		values (?, ?, ?, ?, ?, ?, ?, ?)
		on conflict (identifier) do update set
			recorded_at                      = EXCLUDED.recorded_at,
			series                           = EXCLUDED.series,
			scripture_focus                  = EXCLUDED.scripture_focus,
			scripture_reading                = EXCLUDED.scripture_reading,
			scripture_reading_might_be_focus = EXCLUDED.scripture_reading_might_be_focus,
			speaker                          = EXCLUDED.speaker,
			title                            = EXCLUDED.title
		returning id',
		map { $sermon->$_ } qw(identifier recorded_at series scripture_focus scripture_reading
			scripture_reading_might_be_focus speaker title)
	)->hash->{id});
}

method to_yaml(\@sermons) {
	return Dump [ map { $_->to_hash } @sermons ];
}

method where(Str $clause, @replace) {
	return $self->_build($self->pg->db->query("select * from sermons where $clause", @replace));
}

method _build($query) {
	my @sermons;
	while (my $hash = $query->hash) {
		push @sermons, $self->sermon_class->new(app => $self->app, %$hash);
	}
	\@sermons;
}

method _load_file(Path $file is coerce) {
	$file->basename =~ /\.(\w+)$/;
	my $method = $self->can('_load_' . $1 . '_file')
		or die "Unsupported file type: " . $file;
	return $self->$method(decode_utf8 scalar $file->slurp);
}

method _load_txt_file($file) {
	map { $self->sermon_class->from_txt($self->app, $_) } split /\r?\n\r?\n/, $file;
}

method _load_yaml_file($file) {
	my $yaml = Load $file;
	die "No definitions found in $file, probably malformed YAML" unless $yaml;
	if (ref $yaml eq 'HASH') {
		map { $self->sermon_class->new(app => $self->app, identifier => $_, %{ $yaml->{$_} }) } keys %$yaml;
	}
	else {
		map { $self->sermon_class->new(app => $self->app, %$_) } @$yaml;
	}
	
}

method _load_yml_file($file) {
	return $self->_load_yaml_file($file);
}

1

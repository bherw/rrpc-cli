package App::RRPC::Role::SermonSelector;

use v5.14;
use List::AllUtils qw(uniq);
use Kavorka;
use MooseX::App::Role;

option 'all', is => 'rw', isa => 'Bool';
option 'where', is => 'rw', isa => 'Str';

method selected_sermons {
	my $all   = $self->all;
	my @args  = @{ $self->extra_argv };
	my $where = $self->where;
	my @sermons;

	if ($all && (@args || $where)) {
		say "Can't specify --all and --where or args at the same time" and exit 1;
	}
	if ($where && @args) {
		say "Can't specify --where and args at the same time" and exit 1;
	}

	return $self->sermons->load_all(order => 'recorded_at') if $all;
	return $self->sermons->where($where) if $where;

	if (!@args) {
		my @identifiers;
		for ($self->base_dir->children) {
			if ($_->basename =~ /^(\d{4}-\d\d-\d\d[AP]M)\.\w+$/) {
				push @identifiers, $1;
			}
		}

		for (uniq @identifiers) {
			push @sermons, $self->sermons->load_by_identifier($_)
				|| say "no metadata found for $_, did you forget to import it?" && exit 1;
		}
	}
	else {
		for (@args) {
			if (-f $_) {
				push @sermons, @{ $self->sermons->load_files([$_]) };
			}
			else {
				push @sermons, $self->sermons->load_by_identifier($_)
					|| say "no metadata found for $_, did you forget to import it?" && exit 1;
			}
		}
	}

	say "No sermons specified" and exit 1 unless @sermons;
	\@sermons;
}

1;

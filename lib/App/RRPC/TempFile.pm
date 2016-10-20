package App::RRPC::TempFile;

use common::sense;
use File::Copy qw(move);
use File::Temp;
use parent 'Path::Class::File';

sub new {
	my $class = shift;
	my $temp = File::Temp->new(@_);
	my $self = $class->SUPER::new($temp);
	$self->{temp} = $temp;
	$self;
}

sub move_to {
	my ($self, $dest) = @_;

	return unless move $self->stringify, "${dest}";

	my $new = Path::Class::File->new($dest);
	$self->{$_} = $new->{$_} foreach (qw/ dir file /);

	$self;
}

1;

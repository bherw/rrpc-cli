package App::RRPC::API;

use Moose;
use MooseX::NonMoose;

no strict 'refs';

extends 'Mojo::UserAgent';

has 'api_base', is => 'rw';
has 'access_key', is => 'rw';
has 'ca', is => 'rw', default => sub { \undef };

for my $method (qw(get post put delete)) {
	*$method = sub {
		my $self = shift;
		my $url  = Mojo::URL->new($self->api_base . '/' . shift);
		if ($self->access_key) {
			$url->query->param(access_key => $self->access_key);
		}
		my $tx = $self->${ \"SUPER::$method" }($url, @_);
		$tx->success or die "HTTP error: " . $tx->error->{message};
	}
}

1;

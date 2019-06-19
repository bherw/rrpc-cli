package App::RRPC::API;

use Mojo::Base 'Mojo::UserAgent';

has 'api_base';
has 'access_key';
has 'ca' => sub { \undef }; # Enable CA cert checking -- Mojo disables it by default

for my $method (qw(get patch post put delete)) {
	no strict 'refs';
	*$method = sub {
		my $self = shift;
		my $url  = Mojo::URL->new($self->api_base . '/' . shift);
		if ($self->access_key) {
			$url->query->param(access_key => $self->access_key);
		}
		my $tx = $self->${ \"SUPER::$method" }($url, @_);
		return if $tx->res->code == 404;

		$tx->result->json
	}
}

1;

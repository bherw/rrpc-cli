package App::RRPC::API;

use Moose;
use MooseX::NonMoose;

use common::sense;

no strict 'refs';

extends 'Mojo::UserAgent';

has 'api_base', is => 'rw';
has 'access_key', is => 'rw';
has 'ca', is => 'rw', default => sub { \undef };

for my $method (qw(get patch post put delete)) {
	*$method = sub {
		my $self = shift;
		my $url  = Mojo::URL->new($self->api_base . '/' . shift);
		if ($self->access_key) {
			$url->query->param(access_key => $self->access_key);
		}
		my $tx = $self->${ \"SUPER::$method" }($url, @_);
		return if $tx->res->code == 404;

		my $res = $tx->success or do {
			my $content = $tx->res->content->asset->slurp;
			if ($tx->res->headers->content_type =~ 'text/html') {
				$content = 'content written to error.html';
				$tx->res->content->asset->move_to('error.html');
			}
			die "HTTP error: " . $tx->error->{message} . "\n" . $content;
		};

		$res->json;
	}
}

1;

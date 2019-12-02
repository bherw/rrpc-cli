package App::RRPC::API::Upload;

use Moo;

has [qw(content file filename)], is => 'rw';

1;

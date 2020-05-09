package App::RRPC::Command::upload;

use Kavorka;
use MooseX::App::Command;
use v5.14;

extends 'App::RRPC';
with 'App::RRPC::Role::SermonSelector';

option 'create_series',   is => 'ro', isa => 'Bool', default => 0;
option 'create_speaker',  is => 'ro', isa => 'Bool', default => 0;
option 'overwrite_audio', is => 'ro', isa => 'Bool', default => 0;

method run {
	$|++;
	$self->upload_sermons(
		$self->selected_sermons,
		create_series   => !!$self->create_series,
		create_speaker  => !!$self->create_speaker,
		overwrite_audio => !!$self->overwrite_audio,
	);
}

1;

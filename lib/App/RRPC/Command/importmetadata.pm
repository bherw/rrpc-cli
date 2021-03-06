package App::RRPC::Command::importmetadata;

use Kavorka;
use MooseX::App::Command;
use v5.14;

extends 'App::RRPC';
with 'App::RRPC::Role::SermonSelector';

method run {
	my $term;

	for my $sermon (@{ $self->selected_sermons }) {
		my $tx = $self->pg->db->begin;
		my $old = $self->sermons->load_by_identifier($sermon->identifier);

		if ($old && $old ne $sermon) {
			require Term::ReadLine;
			require Term::UI;
			require Text::Diff;
			$term //= Term::ReadLine->new('rrpc');

			Text::Diff::diff(\($old->to_yaml), \($sermon->to_yaml), {
				FILENAME_A => 'DATABASE ' . $old->identifier,
				FILENAME_B => 'IMPORT ' . $sermon->identifier,
				STYLE      => 'Table',
				OUTPUT     => \*STDOUT,
			});

			my $reply = $term->get_reply(
				prompt  => 'Update existing metadata?',
				choices => [qw(yes no exit)],
				default => 'no',
			);
			exit if $reply eq 'exit';
			next if $reply eq 'no';

			# Update: yes
			$sermon->id($old->id);
		}

		$self->sermons->save($sermon);
		$tx->commit;
	}
}

package Org::To::ANSIText;

use 5.010001;
use strict;
use vars qw($VERSION);
use warnings;
use Log::ger;

use Exporter 'import';
use File::Slurper qw(read_text write_text);
use Org::Document;

use Moo;
with 'Org::To::Role';
extends 'Org::To::Base';

# AUTHORITY
# DATE
# DIST
# VERSION

our @EXPORT_OK = qw(org_to_ansi_text);

our %SPEC;
$SPEC{org_to_ansi_text} = {
    v => 1.1,
    summary => 'Export Org document to text with ANSI color codes',
    description => <<'_',

This is the non-OO interface. For more customization, consider subclassing
Org::To::ANSIText.

_
    args => {
        source_file => {
            summary => 'Source Org file to export',
            schema => ['str' => {}],
        },
        source_str => {
            summary => 'Alternatively you can specify Org string directly',
            schema => ['str' => {}],
        },
        target_file => {
            summary => 'Text file to write to',
            schema => ['str' => {}],
            description => <<'_',

If not specified, text string will be returned.

_
        },
        include_tags => {
            summary => 'Include trees that carry one of these tags',
            schema => ['array' => {of => 'str*'}],
            description => <<'_',

Works like Org's 'org-export-select-tags' variable. If the whole document
doesn't have any of these tags, then the whole document will be exported.
Otherwise, trees that do not carry one of these tags will be excluded. If a
selected tree is a subtree, the heading hierarchy above it will also be selected
for export, but not the text below those headings.

_
        },
        exclude_tags => {
            summary => 'Exclude trees that carry one of these tags',
            schema => ['array' => {of => 'str*'}],
            description => <<'_',

If the whole document doesn't have any of these tags, then the whole document
will be exported. Otherwise, trees that do not carry one of these tags will be
excluded. If a selected tree is a subtree, the heading hierarchy above it will
also be selected for export, but not the text below those headings.

exclude_tags is evaluated after include_tags.

_
        },
        ignore_unknown_settings => {
            schema => 'bool',
        },
    },
};
sub org_to_ansi_text {
    my %args = @_;

    my $doc;
    if ($args{source_file}) {
        $doc = Org::Document->new(
            from_string => scalar read_text($args{source_file}),
            ignore_unknown_settings => $args{ignore_unknown_settings},
        );
    } elsif (defined($args{source_str})) {
        $doc = Org::Document->new(
            from_string => $args{source_str},
            ignore_unknown_settings => $args{ignore_unknown_settings},
        );
    } else {
        return [400, "Please specify source_file/source_str"];
    }

    my $obj = ($args{_class} // __PACKAGE__)->new(
        source_file   => $args{source_file} // '(source string)',
        include_tags  => $args{include_tags},
        exclude_tags  => $args{exclude_tags},
    );

    my $text = $obj->export($doc);
    #$log->tracef("text = %s", $text);
    if ($args{target_file}) {
        write_text($args{target_file}, $text);
        return [200, "OK"];
    } else {
        return [200, "OK", $text];
    }
}

sub export_document {
    my ($self, $doc) = @_;

    my $text = [];
    push @$text, $self->export_elements(@{$doc->children});
    join "", @$text;
}

sub export_block {
    my ($self, $elem) = @_;
    $elem->raw_content;
}

sub export_fixed_width_section {
    my ($self, $elem) = @_;
    $elem->text;
}

sub export_comment {
    my ($self, $elem) = @_;
    "";
}

sub export_drawer {
    my ($self, $elem) = @_;
    # currently not exported
    '';
}

sub export_footnote {
    my ($self, $elem) = @_;
    # currently not exported
    '';
}

sub export_headline {
    my ($self, $elem) = @_;

    my @children = $self->_included_children($elem);

    join("",
         ("*" x $elem->level), " ", $self->export_elements($elem->title), "\n",
         $self->export_elements(@children),
     );
}

sub export_list {
    my ($self, $elem) = @_;

    join("",
         $self->export_elements(@{$elem->children // []}),
     );
}

sub export_list_item {
    my ($self, $elem) = @_;

    my $text = [];

    push @$text, $elem->bullet, " ";

    if ($elem->check_state) {
        push @$text, "\e[1m[", $elem->check_state, "]\e[22m";
    }

    if ($elem->desc_term) {
         push @$text, "\e[1m[", $elem->desc_term, "]\e[22m", " :: ";
    }

    push @$text, $self->export_elements(@{$elem->children}) if $elem->children;

    join "", @$text;
}

sub export_radio_target {
    my ($self, $elem) = @_;
    # currently not exported
    '';
}

sub export_setting {
    my ($self, $elem) = @_;
    # currently not exported
    '';
}

sub export_table {
    my ($self, $elem) = @_;
    $self->export_elements(@{$elem->children // []}),
}

sub export_table_row {
    my ($self, $elem) = @_;
    join "", (
        "|",
        $self->export_elements(@{$elem->children // []}),
        "|\n",
    );
}

sub export_table_cell {
    my ($self, $elem) = @_;

    join "", (
        $self->export_elements(@{$elem->children // []}),
    );
}

sub export_table_vline {
    my ($self, $elem) = @_;
    # currently not exported
    '';
}

sub export_target {
    my ($self, $elem) = @_;
    '';
}

sub export_text {
    my ($self, $elem) = @_;

    my $style = $elem->style;
    my $begin_code = '';
    my $end_code   = '';
    if    ($style eq 'B') { $begin_code = "\e[1m"; $end_code   = "\e[22m" }
    elsif ($style eq 'I') { $begin_code = "\e[3m"; $end_code   = "\e[23m" }
    elsif ($style eq 'U') { $begin_code = "\e[4m"; $end_code   = "\e[24m" }
    elsif ($style eq 'S') { $begin_code = "\e[2m"; $end_code   = "\e[22m" } # strike is rendered as faint
    elsif ($style eq 'C') { }
    elsif ($style eq 'V') { }

    my $text = [];

    push @$text, $begin_code if $begin_code;
    push @$text, $elem->text;
    push @$text, $self->export_elements(@{$elem->children}) if $elem->children;
    push @$text, $end_code   if $end_code;

    join "", @$text;
}

sub export_time_range {
    my ($self, $elem) = @_;

    $elem->as_string;
}

sub export_timestamp {
    my ($self, $elem) = @_;

    $elem->as_string;
}

sub export_link {
    require Filename::Image;
    require URI;

    my ($self, $elem) = @_;

    my $text = [];
    my $link = $elem->link;

    push @$text, "[LINK:$link";
    if ($elem->description) {
        push @$text, " ", $self->export_elements($elem->description);
    }
    push @$text, "]";

    join "", @$text;
}

1;
# ABSTRACT:

=for Pod::Coverage ^(export_.+|before_.+|after_.+)$

=head1 SYNOPSIS

 use Org::To::ANSIText qw(org_to_ansi_text);

 # non-OO interface
 my $res = org_to_ansi_text(
     source_file   => 'todo.org', # or source_str
     #target_file  => 'todo.txt', # default is to return the text in $res->[2]
     #include_tags => [...], # default exports all tags.
     #exclude_tags => [...], # behavior mimics emacs's include/exclude rule
 );
 die "Failed" unless $res->[0] == 200;

 # OO interface
 my $oea = Org::To::ANSIText->new();
 my $text = $oea->export($doc); # $doc is Org::Document object


=head1 DESCRIPTION

Export Org format to ANSI text (text with ANSI escape codes). To customize, you
can subclass this module.

A command-line utility L<org-to-ansi-text> is available in the distribution
L<App::OrgUtils>.


=head1 ATTRIBUTES


=head1 METHODS

=head1 new(%args)

=head2 $exp->export_document($doc) => text

Export document to text.


=head1 SEE ALSO

L<Org::Parser>

L<org-to-ansi-text>

Other Org exporters: L<Org::To::Text>, L<Org::To::HTML>, L<Org::To::VCF>.

=cut

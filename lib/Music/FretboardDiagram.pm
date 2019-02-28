package Music::FretboardDiagram;

# ABSTRACT: Draw fretboard chord diagrams

our $VERSION = '0.0702';

use Moo;
use strictures 2;
use namespace::clean;

use Imager;
use List::MoreUtils 'first_index';
use Music::Chord::Namer 'chordname';

=head1 SYNOPSIS

  use Music::FretboardDiagram;

  my $dia = Music::FretboardDiagram->new(
    chord => 'x02220',
    font  => '/path/to/TTF/font.ttf',
  );
  $dia->draw;

  $dia->chord('xx0232');
  $dia->position(5);
  $dia->outfile('mystery-chord');
  $dia->showname('Xb'); # "X flat"
  $dia->draw;

  $dia = Music::FretboardDiagram->new(
    chord    => '4442',
    position => 3,
    strings  => 4,
    frets    => 6,
    size     => 25,
    outfile  => 'ukulele-chord',
    type     => 'bmp',
    font     => '/path/to/TTF/font.ttf',
    tuning   => [qw/A E C G/],
    horiz    => 1,
    verbose  => 1,
  );
  $dia->draw;

=head1 DESCRIPTION

A C<Music::FretboardDiagram> object draws fretboard chord diagrams including
neck position and chord name annotations for guitar, ukulele, banjo, etc.

Below are examples of a vertical guitar diagram and a horizontal ukulele diagram:

=begin html

<br>
<img src="https://raw.githubusercontent.com/ology/Music-FretboardDiagram/master/chord-diagram.png">
<img src="https://raw.githubusercontent.com/ology/Music-FretboardDiagram/master/ukulele.png">
<br>

=end html

=head1 ATTRIBUTES

=head2 chord

  $dia->chord('xx0232');
  $chord = $dia->chord;

A chord given as a string, where non-zero digits represent frets, C<x> (or C<X>)
indicates a muted string and C<0> (or C<o> or C<O>) indicates an open string.
The default order of the strings is C<654321> from lowest to highest.

Examples:

  C: x32010
  D: xx0232
  E: 022100
  F: xx3211
  G: 320003
  A: x02220
  B: x24442
 
  Cm: xx5543
  Dm: xx0231
  Em: 022000
  Fm: xx3111
  Gm: xx5333
  Am: x02210
  Bm: x24432
 
  C7: x32310
  D7: xx0212
  E7: 020100
  F7: xx1211
  G7: 320001
  A7: x02020
  B7: x21202

=cut

has chord => (
    is => 'rw',
);

=head2 position

  $dia->position(3);
  $position = $dia->position;

The neck position of a chord to be diagrammed.  This number is rendered to the
left of the first fret in vertical mode.  When drawing horizontally, the
position is rendered above the first fret.

Default: 1

=cut

has position => (
    is      => 'rw',
    isa     => \&_positive_int,
    default => sub { 1 },
);

=head2 strings

  $strings = $dia->strings;

The number of strings.

Default: 6

=cut

has strings => (
    is      => 'ro',
    isa     => \&_positive_int,
    default => sub { 6 },
);

=head2 frets

  $frets = $dia->frets;

The number of frets.

Default: 5

=cut

has frets => (
    is      => 'ro',
    isa     => \&_positive_int,
    default => sub { 5 },
);

=head2 size

  $size = $dia->size;

The relative size of the diagram.

Default: 30

=cut

has size => (
    is      => 'ro',
    isa     => \&_positive_int,
    default => sub { 30 },
);

=head2 outfile

  $dia->outfile('chord-042');
  $outfile = $dia->outfile;

The image file name minus the extension.

Default: chord-diagram

=cut

has outfile => (
    is      => 'rw',
    default => sub { 'chord-diagram' },
);

=head2 type

  $type = $dia->type;

The image file extension.

Default: png

=cut

has type => (
    is      => 'ro',
    default => sub { 'png' },
);

=head2 font

  $font = $dia->font;

The TTF font to use when rendering the diagram.

Default: /opt/X11/share/fonts/TTF/VeraMono.ttf

=cut

has font => (
    is      => 'ro',
    default => sub { '/opt/X11/share/fonts/TTF/VeraMono.ttf' },
);

=head2 tuning

  $tuning = $dia->tuning;

An arrayref of the string tuning.  The order of the notes is from highest string
(1st) to lowest (6th).  For accidental notes, use flat (C<b>), not sharp (C<#>).

Default: [ E B G D A E ]

=cut

has tuning => (
    is      => 'ro',
    default => sub { [qw/E B G D A E/] },
);

=head2 horiz

  $horiz = $dia->horiz;

Draw the diagram horizontally.  That is, with the first string at the top and
the 6th string at the bottom, and frets numbered from left to right.

=cut

has horiz => (
    is      => 'ro',
    default => sub { 0 },
);

=head2 fretboard

  $fretboard = $dia->fretboard;

A hashref of the string notes.  This is a computed attribute.

=cut

has fretboard => (
    is       => 'ro',
    init_arg => undef,
);

=head2 showname

  $dia->showname('Xb dim');
  $dia->showname(1); # Reset to computed names
  $showname = $dia->showname;

Show a chord name or not.

Sometimes the computed chord name is not that accurate.  In those cases set the
B<showname> to a string of your choosing before drawing.

Default: 1

=cut

has showname => (
    is      => 'rw',
    default => sub { 1 },
);

=head2 verbose

  $verbose = $dia->verbose;

Monitor the progress of the diagram construction.

Default: 0

=cut

has verbose => (
    is      => 'ro',
    default => sub { 0 },
);

=head1 METHODS

=head2 new

  $dia = Music::FretboardDiagram->new(%arguments);

Create a new C<Music::FretboardDiagram> object.

=head2 BUILD

Construct the B<fretboard> attribute from the B<tuning>.

=cut

sub BUILD {
    my ( $self, $args ) = @_;

    die 'chord length and string number differ'
        if $args->{chord} && length($args->{chord}) != $self->{strings};

    my @scale = qw/C Db D Eb E F Gb G Ab A Bb B/;

    # Make a scale position index corresponding with the given tuning
    my @index = map { my $t = $_; first_index { $t eq $_ } @scale } @{ $self->tuning };

    my %notes;

    my $n = 0;

    for my $i ( @index ) {
        $n++;

        # Make a scale note list for each string
        $notes{$n} = [ map { $scale[ ($i + $_) % @scale ] } 0 .. @scale - 1 ];
    }

    $self->{fretboard} = \%notes;
}

=head2 draw

  $dia->draw;

Render the requested chord diagram as an image file of B<type>.

=cut

sub draw {
    my ($self) = @_;

    if ( $self->horiz ) {
        $self->_draw_horiz;
        return;
    }

    my $WHITE = 'white';
    my $BLUE  = 'blue';
    my $BLACK = 'black';
    my $SPACE = $self->size;

    my @chord;
    my $font;

    # Setup a new image
    my $i = Imager->new(
        xsize => $SPACE + $self->strings * $SPACE - $self->strings,
        ysize => $SPACE + $self->frets * $SPACE - $self->frets,
    );
    $i->box( filled => 1, color => $WHITE );

    if ( -e $self->font ) {
        $font = Imager::Font->new( file => $self->font );
    }
    else {
        warn 'WARNING: Font ', $self->font, " not found\n";
    }

    # Draw the vertical string lines
    for my $string ( 0 .. $self->strings - 1 ) {
        $i->line(
            color => $BLUE,
            x1    => $SPACE + $string * $SPACE,
            y1    => $SPACE,
            x2    => $SPACE + $string * $SPACE,
            y2    => $SPACE + ($self->frets - 1) * $SPACE,
            aa    => 1,
            endp  => 1
        );
    }
 
    # Draw the horizontal fret lines
    for my $fret ( 0 .. $self->frets - 1 ) {
        $i->line(
            color => $BLUE,
            x1    => $SPACE,
            y1    => $SPACE + $fret * $SPACE,
            x2    => $SPACE + ($self->strings - 1) * $SPACE,
            y2    => $SPACE + $fret * $SPACE,
            aa    => 1,
            endp  => 1
        );

        # Indicate the neck position
        if ( $fret == 1 ) {
            $i->string(
                font  => $font,
                text  => $self->position,
                color => $BLACK,
                x     => $SPACE / 4,
                y     => $SPACE * 2 + $SPACE / 4,
                size  => $SPACE / 2,
                aa    => 1,
            );
        }
    }

    # Draw the note/mute markers
    my $string = $self->strings;

    for my $note ( split //, $self->chord ) {
        if ( $note =~ /[xX]/ ) {
            print "X at 0,$string\n" if $self->verbose;

            $i->string(
                font  => $font,
                text  => 'X',
                color => $BLACK,
                x     => $SPACE + ($self->strings - $string) * $SPACE - $SPACE / 6,
                y     => $SPACE - 2,
                size  => $SPACE / 2,
                aa    => 1,
            );
        }
        elsif ( $note =~ /[oO0]/ ) {
            my $temp = $self->fretboard->{$string}[0];
            push @chord, $temp;

            print "O at 0,$string = $temp\n" if $self->verbose;

            $i->string(
                font  => $font,
                text  => 'O',
                color => $BLACK,
                x     => $SPACE + ($self->strings - $string) * $SPACE - $SPACE / 6,
                y     => $SPACE - 2,
                size  => $SPACE / 2,
                aa    => 1,
            );
        }
        else {
            my $temp = $self->fretboard->{$string}[ ($self->position + $note - 1) % @{ $self->fretboard->{1} } ];
            push @chord, $temp;

            print "Dot at $note,$string = $temp\n" if $self->verbose;

            $i->circle(
                color => $BLACK,
                r     => $SPACE / 5,
                x     => $SPACE + ($self->strings - $string) * $SPACE,
                y     => $SPACE + $SPACE / 2 + ($note - 1) * $SPACE,
            );
        }

        # Decrement the current string number
        $string--;
    }

    # Print the chord name if requested
    if ( $self->showname ) {
        my $chord_name = $self->showname eq '1' ? chordname(@chord) : $self->showname;
        print "Chord = $chord_name\n" if $self->verbose;
        $i->string(
            font  => $font,
            text  => $chord_name,
            color => $BLACK,
            x     => $SPACE,
            y     => $self->strings * $SPACE - $SPACE / 3,
            size  => $SPACE / 2,
            aa    => 1,
        );
    }

    $self->_output_image($i);
}

sub _draw_horiz {
    my ($self) = @_;

    my $WHITE = 'white';
    my $BLUE  = 'blue';
    my $BLACK = 'black';
    my $SPACE = $self->size;

    my @chord;
    my $font;

    # Setup a new image
    my $i = Imager->new(
        ysize => $SPACE + $self->strings * $SPACE - $self->strings,
        xsize => $SPACE + $self->frets * $SPACE - $self->frets,
    );
    $i->box( filled => 1, color => $WHITE );

    if ( -e $self->font ) {
        $font = Imager::Font->new( file => $self->font );
    }
    else {
        warn 'WARNING: Font ', $self->font, " not found\n";
    }

    # Draw the horizontal string lines
    for my $string ( 0 .. $self->strings - 1 ) {
        $i->line(
            color => $BLUE,
            y1    => $SPACE + $string * $SPACE,
            x1    => $SPACE,
            y2    => $SPACE + $string * $SPACE,
            x2    => $SPACE + ($self->frets - 1) * $SPACE,
            aa    => 1,
            endp  => 1
        );
    }
 
    # Draw the vertical fret lines
    for my $fret ( 0 .. $self->frets - 1 ) {
        $i->line(
            color => $BLUE,
            y1    => $SPACE,
            x1    => $SPACE + $fret * $SPACE,
            y2    => $SPACE + ($self->strings - 1) * $SPACE,
            x2    => $SPACE + $fret * $SPACE,
            aa    => 1,
            endp  => 1
        );

        # Indicate the neck position
        if ( $fret == 1 ) {
            $i->string(
                font  => $font,
                text  => $self->position,
                color => $BLACK,
                y     => $SPACE / 2 + $SPACE / 5,
                x     => $SPACE * 2 - $SPACE / 5,
                size  => $SPACE / 2,
                aa    => 1,
            );
        }
    }

    # Draw the note/mute markers
    my $string = 1;

    for my $note ( split //, $self->chord ) {
        if ( $note =~ /[xX]/ ) {
            print "X at fret:0, string:$string\n" if $self->verbose;

            $i->string(
                font  => $font,
                text  => 'X',
                color => $BLACK,
                y     => $SPACE + ($self->strings - $string) * $SPACE + $SPACE / 4,
                x     => $SPACE - $SPACE / 2,
                size  => $SPACE / 2,
                aa    => 1,
            );
        }
        elsif ( $note =~ /[oO0]/ ) {
            my $temp = $self->fretboard->{$self->strings - $string + 1}[0];
            push @chord, $temp;

            print "O at fret:0, string:$string = $temp\n" if $self->verbose;

            $i->string(
                font  => $font,
                text  => 'O',
                color => $BLACK,
                y     => $SPACE + ($self->strings - $string) * $SPACE + $SPACE / 4,
                x     => $SPACE - $SPACE / 2,
                size  => $SPACE / 2,
                aa    => 1,
            );
        }
        else {
            my $temp = $self->fretboard->{$self->strings - $string + 1}[ ($self->position + $note - 1) % @{ $self->fretboard->{1} } ];
            push @chord, $temp;

            print "Dot at fret:$note, string:$string = $temp\n" if $self->verbose;

            $i->circle(
                color => $BLACK,
                r     => $SPACE / 5,
                y     => $SPACE + ($self->strings - $string) * $SPACE,
                x     => $SPACE + $SPACE / 2 + ($note - 1) * $SPACE,
            );
        }

        # Increment the current string number
        $string++;
    }

    # Print the chord name if requested
    if ( $self->showname ) {
        my $chord_name = $self->showname eq '1' ? chordname(@chord) : $self->showname;
        print "Chord = $chord_name\n" if $self->verbose;
        $i->string(
            font  => $font,
            text  => $chord_name,
            color => $BLACK,
            x     => $SPACE,
            y     => ($self->strings + 1) * $SPACE - $SPACE / 3,
            size  => $SPACE / 2,
            aa    => 1,
        );
    }

    $self->_output_image($i);
}

sub _output_image {
    my ($self, $img) = @_;
    my $name = $self->outfile . '.' . $self->type;
    $img->write( type => $self->type, file => $name )
        or die "Can't save $name: ", $img->errstr;
}

sub _positive_int {
    my ($arg) = @_;
    die "$arg is not a positive integer" unless $arg =~ /^[1-9]\d*$/;
}

1;
__END__

=encoding utf-8

=head1 THANK YOU

Paweł Świderski for the horizontal drawing suggestion

=head1 SEE ALSO

The F<eg/> files in this distribution

L<Imager>

L<List::MoreUtils>

L<Moo>

L<Music::Chord::Namer>

Similar modules:

L<GD::Tab::Guitar>

L<Music::Image::Chord>

=cut

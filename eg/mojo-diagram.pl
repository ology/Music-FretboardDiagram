#!/usr/bin/env perl

use Mojolicious::Lite;

use Music::FretboardDiagram;
use Imager;

# Usage:
# http://$host/:chord/:position[?showname={0,Chord+Name}]
# Examples:
# http://localhost/002220/1
# http://localhost/012340/1?showname=0
# http://localhost/012340/3?showname=Xb+dim

get '/:chord/:position' => sub {
    my $c = shift;

    my $dia = Music::FretboardDiagram->new(
        chord    => $c->param('chord'),
        position => $c->param('position'),
        showname => $c->param('showname') // 1, # query param
        frets    => 6,
        horiz    => 1,
        image    => 1,
        font     => '/opt/X11/share/fonts/TTF/VeraMono.ttf',
    );
    my $i = $dia->draw;

    my $data;
    $i->write( data => \$data, type => $dia->type )
        or die "Can't write to memory: ", $i->errstr;

    $c->render( data => $data, format => $dia->type );
};

app->start;

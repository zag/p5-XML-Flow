package XML::Flow;

#$Id: Flow.pm,v 1.3 2006/07/26 07:20:46 zag Exp $

=pod

=head1 NAME

XML::Flow - Store (restore) perl data structures in XML stream.

=head1 SYNOPSIS

  #Write XML
  use XML::Flow;
  my $wr = new XML::Flow:: "test.xml";
  $wr->startTag("Root"); #start root tag
  $wr->startTag("Data");
  $wr->write({1=>2},[4..6]);
  $wr->closeTag("Data");
  $wr->closeTag("Root");
  $wr->close;

  #Read
  my $fs = new IO::File:: "<test.xml";
  my $rd = new XML::Flow:: $fs;
  my %tags = (
       Root=>undef,
       Data=>sub { print Dumper(\@_) },
       );
  $rd->read(\%tags);
  $fs->close;

=head1 DESCRIPTION

Easy store and restore perl data structures. It use  XML::Parser for read and XML::Writer for write 
xml.

=head1 METHODS

=cut

use XML::Parser;
use XML::Writer;
use IO::File;
use Data::Dumper;
use warnings;
use Carp;
use Encode;
use strict;
$XML::Flow::VERSION = '0.81';

my $attrs = {
    _file        => undef,
    _file_handle => undef,
    _writer      => undef,
    _events      => {},
    _need_close  => undef
};
### install get/set accessors for this object.
for my $key ( keys %$attrs ) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$key" } = sub {
        my $self = shift;
        $self->{$key} = $_[0] if @_;
        return $self->{$key};
      }
}

=head2 new($filehandle|$filename)

Create a new XML::Flow object. The first parameter should either be a string containing filename, or it should be an open IO::Handle. For example:

 my $wr = new XML::Flow:: "test.xml";

or

 my $fs = new IO::File:: "<test.xml";
 my $rd = new XML::Flow:: $fs;

or

 my $fz = IO::Zlib->new($file, "wb9");
 my $wr = new XML::Flow:: $fz;


=cut

sub new {
    my $class = shift;
    $class = ref $class if ref $class;
    my $self = bless( {}, $class );
    if (@_) {
        my $file = shift;
        if ( ref $file and ( UNIVERSAL::isa( $file, 'IO::Handle' ) or ( ref $file ) eq 'GLOB' )
            or UNIVERSAL::isa( $file, 'Tie::Handle' ) )
        {
            $self->_file_handle($file);
        }
        else {
            $self->_file($file);
        }
    }
    else {
        carp "need filename or filehandle";
        return;
    }
    return $self;
}

sub _get_handle {
    my $self = shift;
    my $mode = shift;
    unless ( $self->_file_handle ) {
        $self->_file_handle( new IO::File:: ( $mode ? ">" : "<" ) . $self->_file );
        $self->_need_close(1);    #close FH when close
    }
    return $self->_file_handle;
}

sub _get_writer {
    my $self = shift;
    unless ( $self->_writer ) {
        my $fh     = $self->_get_handle(1);
        my $writer = new XML::Writer::
          OUTPUT      => $fh,
          DATA_MODE   => 'true',
          DATA_INDENT => 2;
        $writer->xmlDecl("UTF-8");
        $self->_writer($writer)

    }
    return $self->_writer;
}

=head2 startTag($name [, $aname1 => $value1, ...])

Add a start tag to an XML document. This method is wraper for XML::Writer::startTag.


=cut
sub startTag {
    my $self   = shift;
    my $writer = $self->_get_writer;
    return $writer->startTag(@_);
}

sub closeTag {
    my $self   = shift;
    my $writer = $self->_get_writer;
    return $writer->endTag(@_);
}

=head2 endTag([$name])

Add a end tag to an XML document. This method is wraper for XML::Writer::endTag.


=cut

sub endTag {
    my $self   = shift;
    my $writer = $self->_get_writer;
    return $writer->endTag(@_);
}

sub __ref2xml {
    my $self   = shift;
    my $writer = shift;
    my $ref    = shift;
    return unless ref $ref;
    my $type        = 'hashref';
    my $res_as_hash = $ref;
    if ( ref $ref eq 'ARRAY' ) {
        $res_as_hash = {};
        my $key = 0;
        foreach my $val (@$ref) {
            $res_as_hash->{ $key++ } = $val;
        }
        $type = 'arrayref';
    }
    if ( ref $ref eq 'SCALAR' ) {
        $res_as_hash           = {};
        $res_as_hash->{scalar} = $$ref;
        $type                  = 'scalarref';
    }

    $writer->startTag( 'value', type => $type );
    while ( my ( $key, $val ) = each %$res_as_hash ) {
        unless ( defined $val ) {
            $writer->startTag( 'key', name => $key, value => "undef" );
            $writer->endTag('key');
            next;
        }
        $writer->startTag( 'key', name => $key );
        if ( ref($val) ) {
            $self->__ref2xml( $writer, $val );
        }
        else {
            $writer->characters( $self->_utfx2utf($val) );
        }
        $writer->endTag('key');
    }
    $writer->endTag('value');
}

sub _utfx2utf {
    my ( $self, $str ) = @_;
    $str = encode( 'utf8', $str ) if utf8::is_utf8($str);
    return $str;
}

sub _utf2utfx {
    my ( $self, $str ) = @_;
    $str = decode( 'utf8', $str ) unless utf8::is_utf8($str);
    return $str;
}

=head2 write($ref1[, $ref2, ...])

Serilize references to XML. Where $ref is reference to SCALAR, HASH or ARRAY. This method used only for write XML mode.

 $wr->write({1=>2},[4..6]);
 my $a="1";
 $wr->write(\$a);

=cut

sub write {
    my $self   = shift;
    my $writer = $self->_get_writer;
    foreach (@_) {
        $writer->startTag('flow_data_struct');
        $self->__ref2xml( $writer, $_ );
        $writer->endTag('flow_data_struct');

    }
    return;
}

sub _xml2hash_handler {
    my $self = shift;
    my ( $struct, $data, $elem, %attr ) = @_;
    my ( $state, $shared ) = @{$struct}{ 'state', 'shared' };
    my $tag_stack = $shared->{tag_stack} || [];
    $shared->{tag_stack} = $tag_stack;
    for ($state) {

        /1/ && do {
            my $new = { name => $elem, 'attr' => \%attr };
            push @$tag_stack, $new;
            if ( $elem eq 'value' ) {
                $new->{type} = $attr{type};
                for ( $new->{type} ) {
                    /hashref/       && do { $new->{value} = {} }
                      || /arrayref/ && do { $new->{value} = [] }
                }
            }
          }
          || /2/ && do {
            if ( my $current = pop @{$tag_stack} ) {
                push @{$tag_stack}, $current;
                if ( $current->{name} eq 'key' ) {
                    unless ( ref $current->{value} ) {
                        $current->{value} .= $elem;
                        return;    #clear return value
                    }
                }

            }

          }
          || /3/ && do {
            if ( my $current = pop @{$tag_stack} ) {
                my $parent = pop @{$tag_stack};
                die "Stack error " . Dumper() unless $current->{name} eq $elem;
                if ( $elem eq 'key' ) {
                    push @{$tag_stack}, $parent;
                    my $ref_val;
                    $current->{value} = undef
                      if ( exists $current->{attr}->{value}
                        and $current->{attr}->{value} eq 'undef' );
                    for ( $parent->{type} ) {
                        /hashref/ && do {
                            $parent->{value} ||= {};
                            $parent->{value}->{ $current->{attr}->{name} } = $current->{value};
                          }
                          || /arrayref/ && do {
                            $parent->{value} ||= [];
                            ${ $parent->{value} }[ $current->{attr}->{name} ] =
                              $current->{value};
                          }
                          || /scalarref/ && do {
                            $parent->{value} = \$current->{value};
                          }
                    }

                }
                elsif ( $elem eq 'value' ) {
                    if ($parent) {
                        push @{$tag_stack}, $parent;
                        $parent->{value} = $current->{value};
                    }
                    else {
                        $self->_parse_stream( { %$struct, state => 4 }, $current->{value} );
                    }

                }

            }
            else { die "empty stack !" . Dumper( \@_ ) }
          }
    }    #for
}    #sub

sub _parse_stream {
    my $self = shift;
    my ( $struct, $data, $elem, %attr ) = @_;
    my ( $state, $shared, $tags ) = @{$struct}{ 'state', 'shared', 'tags' };
    my $stream_stack = $shared->{stream_stack} || [];
    $shared->{stream_stack} = $stream_stack;
    if ( $state == 4 ) {
        my $current = pop @{$stream_stack};
        push @{ $current->{value} }, $data;
        push @{$stream_stack}, $current;
        $self->_events(
            {
                'curr' => sub { $self->_parse_stream(@_) }
            }
        );
        return;
    }
    if ( $elem eq 'flow_data_struct' ) {
        if ( $state == 1 ) {
            $self->_events(
                {
                    'curr' => sub { $self->_xml2hash_handler(@_) }
                }
            );
        }
        else {

            # Close flow;
        }
        return;
    }
    if ( $state == 1 && exists( $tags->{$elem} ) ) {
        push @{$stream_stack}, { name => $elem, attr => \%attr };
    }
    if ( $state == 3 ) {
        my $current = pop @{$stream_stack};
        return unless defined $tags->{$elem};
        return unless my $handler = $tags->{ $current->{name} };
        print 'ERROR stack for ' . $elem . "->" . $current->{name}
          unless $current->{name} eq $elem;
        my $parent = pop @{$stream_stack};
        my @res = ( $handler->( $current->{attr}, @{ $current->{value} } ) );
        push @{ $parent->{value} }, @res if scalar @res;
        push @{$stream_stack}, $parent;
    }
}

sub _handle_ev {
    my $self   = shift;
    my $events = $self->_events;
    return $events->{'curr'}->(@_);
}

=head2 read({tag1=>sub1{}[, tag2=>\&sub2 })

Run XML parser. Argument is a reference to hash with tag => handler.
If handler eq undef, then tag ignore. If subroutine return non undef result, it passed to parent
tag handler. Handler called with args: ( {hash of attributes}, <reference to data> [,<reference to data>] ).
For example:

Source xml :

 <?xml version="1.0" encoding="UTF-8"?>
 <Root>
  <Obj>
    <Also>
      <flow_data_struct>
        <value type="scalarref">
          <key name="scalar">3</key>
        </value>
      </flow_data_struct>
      <flow_data_struct>
        <value type="hashref">
          <key name="1" value="undef"></key>
        </value>
      </flow_data_struct>
    </Also>
  </Obj>
 </Root>

Read code:

 my $rd = new XML::Flow:: "test.xml";
 my %tags = (
    Root=>undef,
    Obj=>sub { print Dumper(\@_) },
    Also=>sub { 
        shift; #reference to hash of attributes
        return @_},
    );
 $rd->read(\%tags);
 $rd->close;

Output:

 $VAR1 = [
          {}, #reference to hash of xml tag attributes
          \'3',
          {
            '1' => undef
          }
        ];

=cut

sub read {
    my $self    = shift;
    my $tags    = shift or return;
    my $file_in = $self->_get_handle();
    $self->_events(
        {
            'curr' => sub { $self->_parse_stream(@_) }
        }
    );
    my $shared = {};
    my $parser = new XML::Parser(
        Handlers => {
            Start => sub {
                $self->_handle_ev( { state => 1, shared => $shared, tags => $tags }, @_ );
            },
            Char => sub {
                $self->_handle_ev( { state => 2, shared => $shared, tags => $tags }, @_ );
            },
            End => sub {
                $self->_handle_ev( { state => 3, shared => $shared, tags => $tags }, @_ );
            },
        }
    );
    $parser->parse($file_in);

}

=head2 close()

Close all handlers (including internal).

=cut

sub close {
    my $self = shift;
    $self->_file_handle->close if $self->_need_close and $self->_file_handle;
}

1;
__END__


=head1 SEE ALSO

XML::Parser, XML::Writer

=head1 AUTHOR

Zahatski Aliaksandr, <zag@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Zahatski Aliaksandr

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut


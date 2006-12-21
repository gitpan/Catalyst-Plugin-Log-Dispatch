package Catalyst::Plugin::Log::Dispatch;

use warnings;
use strict;

our $VERSION = '0.03';

use base 'Catalyst::Base';

use NEXT;
use IO::Handle;

# Module implementation here
use Data::Dumper;

sub setup {
    my $c = shift;

    my $old_log = undef;
    if ( $c->log and ref( $c->log ) eq 'Catalyst::Log' ) {
        $old_log = $c->log;
    }
    $c->log( Catalyst::Plugin::Log::Dispatch::Backend->new );

    unless ( ref( $c->config->{'Log::Dispatch'} ) eq 'ARRAY' ) {
        push(
            @{ $c->config->{'Log::Dispatch'} },
            {   class     => 'STDOUT',
                name      => 'default',
                min_level => 'debug'
            }
        );

    }
    foreach my $tlogc ( @{ $c->config->{'Log::Dispatch'} } ) {
        my %logc = %{$tlogc};
        if ( $logc{'class'} eq 'STDOUT' or $logc{'class'} eq 'STDERR' ) {
            my $io = IO::Handle->new;
            $io->fdopen( fileno( $logc{'class'} ), 'w' );
            $logc{'class'}  = 'Handle';
            $logc{'handle'} = $io;
        }
        my $class = sprintf( "Log::Dispatch::%s", $logc{'class'} );
        delete $logc{'class'};
        if ( ref( $logc{'callbacks'} ) ne 'CODE' ) {
            my $method = sprintf( '%s_callback', $logc{'callbacks'} || '' );
            unless ( $c->log->can($method) ) {
                $method = 'linebreak_callback';
            }
            $method = "Catalyst::Plugin::Log::Dispatch\:\:Backend::${method}";
            $logc{'callbacks'} = \&{"$method"};
        }
        eval("use $class;");
        die "$@" if ($@);
        $c->log->add( $class->new(%logc) );
    }
    if ($old_log) {
        my @old_logs;
        foreach my $line ( split /\n/, $old_log->body ) {
            if ( $line =~ /^\[(\w+)] (.+)$/ ) {
                push( @old_logs, { level => $1, msg => [$2] } );
            }
            else {
                push( @{ $old_logs[-1]->{'msg'} }, $line );
            }
        }
        foreach my $line (@old_logs) {
            my $level = $line->{'level'};
            $c->log->$level( join( "\n", @{ $line->{'msg'} } ) );
        }
    }
    $c->NEXT::setup(@_);
}

1;

package Catalyst::Plugin::Log::Dispatch::Backend;

use strict;

use base qw/Log::Dispatch Class::Accessor::Fast/;

use Time::HiRes qw/gettimeofday/;
use Data::Dump;
use Data::Dumper;

{
    foreach my $l (qw/debug info warn error fatal/) {
        my $name = $l;
        $name = 'warning'  if ( $name eq 'warn' );
        $name = 'critical' if ( $name eq 'fatal' );

        no strict 'refs';
        *{"is_${l}"} = sub {
            my $self = shift;
            return $self->level_is_valid($name);
        };
    }
}

sub new {
    my $pkg  = shift;
    my $this = $pkg->SUPER::new(@_);
    $this->mk_accessors(qw/abort/);
    return $this;
}

sub warn {
    my $self = shift;
    return $self->warning(@_);
}

sub fatal {
    my $self = shift;
    return $self->critical(@_);
}

sub dumper {
    my $self = shift;
    return $self->debug( Data::Dumper::Dumper(@_) );
}

sub _dump {
    my $self = shift;
    return $self->debug( Data::Dump::dump(@_) );
}

sub level_is_valid {
    my $self = shift;
    return 0 if ( $self->abort );
    return $self->SUPER::level_is_valid(@_);
}

sub _flush {
    my $self = shift;
    if ( $self->abort ) {
        $self->abort(undef);
    }
}

sub timestamp_callback {
    my %p = @_;

    $p{'message'} .= "\n" unless ( $p{'message'} =~ /\n$/ );
    my @localtime = localtime();
    return sprintf(
        "[%04d-%02d-%02d %02d:%02d:%3.3f][%d][%s] %s",
        $localtime[5] + 1900,
        $localtime[4] + 1,
        $localtime[3], $localtime[2], $localtime[1], $localtime[0] + (gettimeofday)[1] / 1000000,
        $$, $p{'level'}, $p{'message'}
    );
}

sub linebreak_callback {
    my %p = @_;
    $p{'message'} .= "\n" unless ( $p{'message'} =~ /\n$/ );
    return "[$p{'level'}] $p{'message'}";
}

1;    # Magic true value required at end of module
__END__


=head1 NAME

Catalyst::Plugin::Log::Dispatch - Log module of Catalyst that uses Log::Dispatch


=head1 VERSION

This document describes Catalyst::Plugin::Log::Dispatch version 2.15


=head1 SYNOPSIS

    package MyApp;

    use Catalyst qw/Log::Dispatch/;

configuration in source code

    MyApp->config->{ Log::Dispatch } = [
        {
         class     => 'File',
         name      => 'file',
         min_level => 'debug',
         filename  => MyApp->path_to('debug.log'),
         callbacks => 'timestamp',
        }];

in myapp.yml

    Log::Dispatch:
     - class: File
       name: file
       min_level: debug
       filename: __path_to(debug.log)__
       mode: append
       callbacks: timestamp

If you use L<Catalyst::Plugin::ConfigLoader>,
please load this module after L<Catalyst::Plugin::ConfigLoader>.

=head1 DESCRIPTION

Catalyst::Plugin::Log::Dispatch is a plugin to use Log::Dispatch from Catalyst.

=head1 CONFIGURATION

It is same as the configuration of Log::Dispatch excluding "class" and "callbacks".

=over

=item class

The class name to Log::Dispatch::* object.
Please specify the name just after "Log::Dispatch::" of the class name.

=item callbacks

When the code reference is specified, it is same as the configuration of Log::Dispatch.
"timestamp" and "linebreak" can be used in addition to the code reference.

=back

=head1 DEPENDENCIES

L<Catalyst>, L<Log::Dispatch>

=head1 AUTHOR

Shota Takayama  C<< <shot[at]bindstorm.jp> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006, Shota Takayama C<< <shot[at]bindstorm.jp> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut


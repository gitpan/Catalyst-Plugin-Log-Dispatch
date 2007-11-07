package Catalyst::Plugin::Log::Dispatch;

use warnings;
use strict;

our $VERSION = '0.07';

use base 'Catalyst::Base';

use UNIVERSAL::require;

use NEXT;
use IO::Handle;

BEGIN { $Log::Dispatch::Config::CallerDepth = 1 if(Log::Dispatch::Config->use); }

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
                min_level => 'debug',
                format    => '[%p] %m%n'
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
        $logc{'callbacks'} = [$logc{'callbacks'}] if(ref($logc{'callbacks'}) eq 'CODE');
        
        if(exists $logc{'format'} and $Log::Dispatch::Config::CallerDepth ) {
            my $callbacks = Log::Dispatch::Config->format_to_cb($logc{'format'},0);
            if(defined $callbacks) {
                $logc{'callbacks'} = [] unless($logc{'callbacks'});
                push(@{$logc{'callbacks'}}, $callbacks);
            }
        }
        elsif(!$logc{'callbacks'}) {
            $logc{'callbacks'} = sub { my %p = @_; return "$p{message}\n"; };
        }
        
        $class->use or die "$@";
        $c->log->add( $class->new(%logc) );
    }
    if ($old_log && defined $old_log->body) {
        my @old_logs;
        foreach my $line ( split /\n/, $old_log->body ) {
            if ( $line =~ /^\[(\w+)] (.+)$/ ) {
                push( @old_logs, { level => $1, msg => [$2] } );
            }
            elsif( $line =~ /^\[(\w{3} \w{3}[ ]{1,2}\d{1,2}[ ]{1,2}\d{1,2}:\d{2}:\d{2} \d{4})\] \[catalyst\] \[(\w+)\] (.+)$/ ) {
                push( @old_logs, { level => $2, msg => [$3] } );
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

        *{"$l"} = sub {
            my $self = shift;
            my %p = (level => $name,
                     message => "@_");
            
            foreach (keys %{ $self->{outputs} }) {
                my %h = %p;
                $h{name} = $_;
                $h{message} = $self->{outputs}{$_}->_apply_callbacks(%h)
                    if($self->{outputs}{$_}->{callbacks});
                push(@{$self->_body}, \%h);
            }
        };
    }
}

sub new {
    my $pkg  = shift;
    my $this = $pkg->SUPER::new(@_);
    $this->mk_accessors(qw/abort _body/);
    $this->_body([]);
    return $this;
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
    if ( $self->abort || !(scalar @{$self->_body})) {
        $self->abort(undef);
    }
    else {
        foreach my $p (@{$self->_body}) {
            $self->{outputs}{$p->{name}}->log_message(%{$p});
        }
    }
    $self->_body([]);
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
         format    => '[%p] %m %n',
        }];

in myapp.yml

    Log::Dispatch:
     - class: File
       name: file
       min_level: debug
       filename: __path_to(debug.log)__
       mode: append
       format: '[%p] %m %n'

If you use L<Catalyst::Plugin::ConfigLoader>,
please load this module after L<Catalyst::Plugin::ConfigLoader>.

=head1 DESCRIPTION

Catalyst::Plugin::Log::Dispatch is a plugin to use Log::Dispatch from Catalyst.

=head1 CONFIGURATION

It is same as the configuration of Log::Dispatch excluding "class" and "format".

=over

=item class

The class name to Log::Dispatch::* object.
Please specify the name just after "Log::Dispatch::" of the class name.

=item format

It is the same as the format option of Log::Dispatch::Config.

=back

=head1 DEPENDENCIES

L<Catalyst>, L<Log::Dispatch>, L<Log::Dispatch::Config>

=head1 AUTHOR

Shota Takayama  C<< <shot[at]bindstorm.jp> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006, Shota Takayama C<< <shot[at]bindstorm.jp> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut


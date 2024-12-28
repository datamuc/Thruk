package Thruk::Utils::Bash;

=head1 NAME

Thruk::Utils::Bash - Handles bash completion

=head1 DESCRIPTION

Bash completion for Thruk

=cut

use warnings;
use strict;
use Encode qw(encode_utf8);

use Thruk::Base ();
use Thruk::Utils::Encode ();
use Thruk::Utils::IO ();

##############################################

=head1 METHODS

=head2 complete

  complete()

returns bash completion

=cut
sub complete {
    my $comp_words = [split(/\s+/mx, $ENV{'COMP_WORD_JOINED'})];
    my $comp_cword = $ENV{'COMP_CWORD'};
    return(0) unless defined $comp_cword;
    my $cur        = $comp_words->[$comp_cword] || ''; # word under the cursur
    my $result     = [];
    $result        = _complete_rest_path($comp_words, $comp_cword, $cur);
    $result        = Thruk::Base::array_uniq($result);
    my $output     = encode_utf8(Thruk::Utils::Encode::decode_any(join("\n", @{$result})));
    binmode STDOUT;
    print STDOUT $output;
    return(0);
}

##############################################
sub _complete_rest_path {
    my($comp_words, $comp_cword, $cur) = @_;
    my $result    = [];
    my $rest_tree = {};
    my $urls      = Thruk::Base::array_uniq([split(/\n/mx, Thruk::Utils::IO::cmd("$0 rest '/csv/index?columns=url&headers=0'"))]);
    for my $url (@{$urls})  {
        _add_rest_tree($rest_tree, $url);
    }

    my $result_prefix = '';
    my @path = split(/(\/)/mx, $cur);

    # split leaves an leading empty element, remove it
    if(defined $path[0] && $path[0] eq '') { shift @path; }
    # trim trailing text which is not yet terminated by trailing /
    if(scalar @path > 0 && $path[scalar @path - 2] eq '/') {
        pop @path;
    }

    # strip known prefixes
    for my $prefix (qw/csv xls/) {
        if(defined $path[1] && $path[1] eq $prefix) {
            shift @path;
            $result_prefix .= '/'.shift @path;
        }
        $rest_tree->{$prefix} = {};
    }
    for my $prefix (qw/site sites backend backends/) {
        if(defined $path[1] && $path[1] eq $prefix && defined $path[4]) {
            shift @path;
            $result_prefix .= '/'.shift @path;
            shift @path;
            $result_prefix .= '/'.shift @path;
        }
        $rest_tree->{$prefix} = {};
    }

    # complete /sites/...<tab>
    if($path[scalar @path - 2] && $path[scalar @path - 2] =~ m%^(sites?|backends?)$%mx) {
        my $key = $1;
        for my $site (split(/\n/mx, Thruk::Utils::IO::cmd("$0 rest '/csv/processinfo/?columns=peer_key,peer_name&headers=0'"))) {
            my($id,$name) = split(';', $site, 2);
            $rest_tree->{$key}->{$id}   = {};
            $rest_tree->{$key}->{$name} = {};
        }
    }

    my $prev  = $path[scalar @path - 2];
    my $last;
    while(my $p = shift @path) {
        next if $p eq '/';
        if(scalar @path > 0) {
            # we are in the middle of the tree, exact matches only
            if($rest_tree->{$p}) {
                $rest_tree = $rest_tree->{$p};
                $result_prefix = $result_prefix.'/'.$p;
            } else {
                if($last) {
                    my $replaced = 0;
                    for my $replace (qw/<name> <host> <host_name> <service>/) {
                        if($rest_tree->{$replace}) {
                            $rest_tree = $rest_tree->{$replace};
                            $result_prefix = $result_prefix.'/'.$p;
                            $replaced = 1;
                            last;
                        }
                    }
                    next if $replaced;
                }
                $rest_tree = {};
                last;
            }
        }
        $last = $p;
    }

    for my $key (sort keys %{$rest_tree}) {
        next if $key eq '.';
        if($key =~ m%^<(.*?)>$%mx) {
            my $expanded = _expand_rest_objects($prev);
            for my $e (@{$expanded}) {
                push @{$result}, $result_prefix.'/'.$e.'/';
            }
            next;
        }
        if(!$rest_tree->{$key}->{'.'}) {
            push @{$result}, $result_prefix.'/'.$key.'/';
        } else {
            push @{$result}, $result_prefix.'/'.$key;
            if(scalar keys %{$rest_tree->{$key}} > 1) {
                push @{$result}, $result_prefix.'/'.$key.'/';
            }
        }
    }

    return($result);
}

##############################################
sub _add_rest_tree {
    my($rest_tree, $url) = @_;
    my @path = split(/\//mx, $url);
    if(defined $path[0] && $path[0] eq '') { shift @path; }
    while(my $p = shift @path) {
        $rest_tree->{$p} = {} unless $rest_tree->{$p};
        $rest_tree = $rest_tree->{$p};
        if(scalar @path == 0) {
            $rest_tree->{'.'} = 1;
        }
    }
    return;
}

##############################################
sub _expand_rest_objects {
    my($type) = @_;
    $type =~ s/s$//gmx;
    if($type eq 'service') { $type = 'host'; }
    if($type =~ /^(host|contact|contactgroup|hostgroup|servicegroup|timeperiod|command)$/mx) {
        return([split(/\n/mx, Thruk::Utils::IO::cmd("$0 rest '/csv/${type}s/?columns=name&headers=0'"))]);
    }
    return([split(/\n/mx, Thruk::Utils::IO::cmd("$0 rest '/csv/hosts/$type/services?columns=description&headers=0'"))]);
}

1;

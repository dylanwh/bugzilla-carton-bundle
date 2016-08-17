package Dockerfile;
use strict;
use warnings;
use base qw(Exporter);
use Carp;
use Cwd 'realpath';
use File::Copy 'copy';
use File::Basename;
use FindBin;
use v5.10.1;

BEGIN { chdir $FindBin::Bin };

our $BASE_DIR = realpath("$FindBin::Bin/..");
our $WORK_DIR = '/opt/bugzilla';
our $GIT_REPO = 'git://github.com/dylanwh/bmo.git';
our $GIT_BRANCH = 'bug-1283930';
our $GEN_CPANFILE_ARGS = '';

our @EXPORT = qw(
    FROM RUN CMD COPY ADD MAINTAINER 
    DOCKER_ENV build_bundle $BASE_DIR
    WORKDIR
    add_script comment
    before_clone after_clone

    $WORK_DIR $GIT_REPO $GIT_BRANCH
    $GEN_CPANFILE_ARGS
);

my %env;
sub _CMD (@) {
    my ($keyword, @args) = @_;
    if (@args == 1 && ref $args[0] && ref $args[0] eq 'ARRAY') {
        say $keyword, ' [', join(', ', map { docker_quote($_) } @{$args[0]}), ']';
    } else {
        say join(' ', $keyword, map { docker_arg($_, $keyword) } @args)
    }
}

sub DOCKER_ENV ($$) {
    my ($k, $v) = @_;
    $env{$k} = '$'.$k;;
    _CMD('ENV', $k, $v);
}

sub FROM ($)       { _CMD 'FROM', @_ }
sub ADD ($;$)       { _CMD 'ADD', @_ }
sub COPY ($;$)      { _CMD 'COPY', @_ }
sub MAINTAINER ($) { _CMD 'MAINTAINER', @_ }
sub WORKDIR ($)    { _CMD 'WORKDIR', @_ }
sub RUN ($)        { _CMD 'RUN', @_ }
sub CMD ($)        { _CMD 'CMD', @_ }

my $before_clone;
sub before_clone (&) {
    my ($code) = @_;
    $before_clone = $code;
}

my $after_clone;
sub after_clone (&) {
    my ($code) = @_;
    $after_clone = $code;
}

sub comment ($) {
    my ($comment) = @_;
    $comment =~ s/^\s*/# /gm;
    $comment =~ s/\n+$//s;
    say $comment;
}

sub build_perl_and_carton {
    comment "build perl and carton";
    DOCKER_ENV PERL_DIR => '/opt/vanilla-perl';
    DOCKER_ENV PERL     => '$PERL_DIR/bin/perl';
    DOCKER_ENV CARTON   => '$PERL_DIR/bin/carton';

    ADD 'https://raw.github.com/tokuhirom/Perl-Build/master/perl-build', '/usr/local/bin/perl-build';
    ADD 'https://raw.githubusercontent.com/miyagawa/cpanminus/master/cpanm', '/usr/local/bin/cpanm';
    RUN 'chmod a+x /usr/local/bin/perl-build /usr/local/bin/cpanm';
    add_script('build-vanilla-perl');

    RUN 'build-vanilla-perl';
    RUN '$PERL /usr/local/bin/cpanm --notest --quiet Carton App::FatPacker File::pushd';
}

sub build_bundle {
    build_perl_and_carton();

    comment "git clone";
    $before_clone->() if $before_clone;
    DOCKER_ENV BUGZILLA_DIR => $WORK_DIR;
    RUN ["git", "clone", "-b", $GIT_BRANCH, $GIT_REPO, $WORK_DIR];
    WORKDIR $WORK_DIR;
    $after_clone->() if $after_clone;

    RUN '$PERL Makefile.PL';

    if (-f 'cpanfile') {
        comment "override repository's cpanfile";
        COPY 'cpanfile', 'cpanfile';
    }
    elsif ($GEN_CPANFILE_ARGS) {
        comment "generate new cpanfile using args";
        RUN "make cpanfile GEN_CPANFILE_ARGS='$GEN_CPANFILE_ARGS'";
    }

    COPY 'cpanfile.snapshot', 'cpanfile.snapshot' if -f 'cpanfile.snapshot';

    add_script('probe-libs');
    add_script('scan-libs');
    add_script('probe-packages');
    add_script('build-bundle');

    DOCKER_ENV NAME => basename($FindBin::Bin);
    CMD 'build-bundle';
}

sub add_script {
    my ($name) = @_;
    copy("$BASE_DIR/scripts/$name", "$name.tmp") or die "copy failed: $!";
    COPY "$name.tmp", "/usr/local/bin/$name";
    RUN "chmod a+x /usr/local/bin/$name";
}

sub docker_arg {
    my ($item, $keyword) = @_;
    my $prefix = ' ' x (length($keyword) + 1);
    $item =~ s/^\s+//gs;
    $item =~ s/\s+$//gs;
    $item =~ s/\n[ \t]*/ \\\n$prefix/gs;
    while ($item =~ /[^\\]\$(\w+)/g) {
        croak "Undefined variable: \$$1" unless $env{$1};
    }
    return $item;
}

sub docker_quote {
    my ($item) = @_;
    $item =~ s/(["\\])/\\$1/gs;
    $item =~ s/\n/\\n/gs;
    return qq{"$item"};
}
1;

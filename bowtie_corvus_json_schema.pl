#!/usr/bin/env perl
# A Bowtie (https://github.com/bowtie-json-schema/bowtie) harness for JSON::Schema::Corvus, the Corvus JSON Schema
# evaluator for Perl: the pure-Perl package, or with CORVUS_PACKAGE=JSON::Schema::Corvus::XS the binding to the
# corvus-json-schema C library (the two have one API).
#
# It speaks IHOP (one JSON request per line on standard input, one response per line on standard output):
# - start reports the implementation and its dialects;
# - dialect sets the dialect for schemas without $schema;
# - run compiles the case's schema with the case's registry as the document resolver and validates each instance
#   (for annotations output, through a verbose collector, reporting each annotation with its instance location and
#   #... keyword location);
# - stop exits.
#
# The schema, the instances and the registry's documents are cut from each request as the JSON text Bowtie wrote, so
# they reach the validator unchanged (numbers included).
use strict;
use warnings;

my $PACKAGE = $ENV{CORVUS_PACKAGE} || 'JSON::Schema::Corvus';
(my $file = "$PACKAGE.pm") =~ s{::}{/}g;
require $file;
require JSON::PP;

binmode STDIN, ':raw';
binmode STDOUT, ':raw';
$| = 1;

my %DIALECTS = (
  'https://json-schema.org/draft/2020-12/schema' => 'draft2020-12',
  'https://json-schema.org/draft/2019-09/schema' => 'draft2019-09',
  'http://json-schema.org/draft-07/schema#'      => 'draft7',
  'http://json-schema.org/draft-06/schema#'      => 'draft6',
  'http://json-schema.org/draft-04/schema#'      => 'draft4',
);
my @DIALECT_ORDER = sort { $DIALECTS{$b} cmp $DIALECTS{$a} } keys %DIALECTS;

my $JSON = JSON::PP->new->utf8->canonical->allow_nonref;

# A JSON value, matched where pos is (a recursive pattern over the JSON grammar).
my $VALUE = qr{
  (?<value> [\x20\t\r\n]* (?: (?&string) | (?&number) | true | false | null | (?&object) | (?&array) ) [\x20\t\r\n]* )
  (?(DEFINE)
    (?<string> " (?: [^"\\] | \\. )* " )
    (?<number> -? (?: 0 | [1-9][0-9]* ) (?: \. [0-9]+ )? (?: [eE] [+-]? [0-9]+ )? )
    (?<object> \{ [\x20\t\r\n]* (?: (?&string) [\x20\t\r\n]* : (?&value) (?: , [\x20\t\r\n]* (?&string) [\x20\t\r\n]* : (?&value) )* )? \} )
    (?<array> \[ [\x20\t\r\n]* (?: (?&value) (?: , (?&value) )* )? \] )
  )
}xs;

sub trimmed { my ($s) = @_; $s =~ s/\A[\x20\t\r\n]+//; $s =~ s/[\x20\t\r\n]+\z//; $s }

# The members of a JSON object's text: [name, value text] in order.
sub members {
  my ($text) = @_;
  $text = trimmed($text);
  return () unless $text =~ /\A\{/;
  my @out;
  pos($text) = 1;
  while (1) {
    $text =~ /\G[\x20\t\r\n]*/gc;
    last if $text =~ /\G\}/gc;
    $text =~ /\G("(?:[^"\\]|\\.)*")[\x20\t\r\n]*:/gc or last;
    my $name = $JSON->decode($1);
    my $start = pos($text);
    $text =~ /\G$VALUE/gc or last;
    push @out, [ $name, trimmed(substr($text, $start, pos($text) - $start)) ];
    $text =~ /\G,/gc;
  }
  return @out;
}

# The items of a JSON array's text, as texts.
sub items {
  my ($text) = @_;
  $text = trimmed($text);
  return () unless $text =~ /\A\[/;
  my @out;
  pos($text) = 1;
  while (1) {
    $text =~ /\G[\x20\t\r\n]*/gc;
    last if $text =~ /\G\]/gc;
    my $start = pos($text);
    $text =~ /\G$VALUE/gc or last;
    push @out, trimmed(substr($text, $start, pos($text) - $start));
    $text =~ /\G,/gc;
  }
  return @out;
}

sub member { my ($text, $name) = @_; for (members($text)) { return $_->[1] if $_->[0] eq $name } undef }

sub fail { print STDERR "$_[0]\n"; exit 1 }

sub first_line { my ($path) = @_; open my $f, '<', $path or return undef; my $l = <$f>; chomp $l if defined $l; $l }

sub error_text {
  my ($e) = @_;
  my $text = ref $e && eval { $e->can('message') } ? $e->message : "$e";
  $text =~ s/\s+\z//;
  return $text;
}

# A JSON pointer token unescaped, and a keyword token percent-encoded as a URI fragment.
sub unescaped_token { my ($t) = @_; $t =~ s/~1/\//g; $t =~ s/~0/~/g; $t }

sub percent_encoded {
  my ($s) = @_;
  utf8::encode($s) if utf8::is_utf8($s);
  $s =~ s/([^A-Za-z0-9\-._~!\$&'()*+,;=:\@\/?])/sprintf('%%%02X', ord $1)/ge;
  return $s;
}

# The annotations of a verbose collector (instance location, then keyword as a JSON pointer token, then schema
# location as a #... fragment; the same in every Corvus implementation) as Bowtie lists them: each with its keyword
# unescaped, and its keyword location the schema location's fragment, / and the keyword token, percent-encoded as the
# fragment is.
sub annotations_of {
  my ($collector) = @_;
  my $grouped = $collector->annotations_json;
  utf8::encode($grouped) if utf8::is_utf8($grouped);
  my @out;
  for my $by_instance (members($grouped)) {
    for my $by_keyword (members($by_instance->[1])) {
      for my $by_location (members($by_keyword->[1])) {
        push @out, '{"keyword":' . $JSON->encode(unescaped_token($by_keyword->[0]))
          . ',"instanceLocation":' . $JSON->encode($by_instance->[0])
          . ',"keywordLocation":' . $JSON->encode($by_location->[0] . '/' . percent_encoded($by_keyword->[0]))
          . ',"annotation":' . $by_location->[1] . '}';
      }
    }
  }
  return '[' . join(',', @out) . ']';
}

sub start {
  (my $dist = $PACKAGE) =~ s/::/-/g;
  my $version = $PACKAGE->VERSION;
  $version =~ s/\Av//;
  my $language_version = sprintf('%vd', $^V);
  $language_version .= ' (C library ' . JSON::Schema::Corvus::XS::library_version_string() . ')'
    if $PACKAGE eq 'JSON::Schema::Corvus::XS';
  my %implementation = (
    language => 'perl',
    # The distribution's name: Bowtie's names have no ::.
    name => $dist,
    version => $version,
    homepage => 'https://github.com/corvus-dotnet/Corvus.JsonSchema',
    documentation => "https://metacpan.org/dist/$dist",
    issues => 'https://github.com/corvus-dotnet/Corvus.JsonSchema/issues',
    source => 'https://github.com/corvus-dotnet/Corvus.JsonSchema',
    dialects => [@DIALECT_ORDER],
    language_version => $language_version,
  );
  my $os = first_line('/proc/sys/kernel/ostype');
  my $os_version = first_line('/proc/sys/kernel/osrelease');
  $implementation{os} = $os if defined $os;
  $implementation{os_version} = $os_version if defined $os_version;
  return $JSON->encode({ version => 1, implementation => \%implementation });
}

sub run {
  my ($line, $dialect) = @_;
  my $seq = member($line, 'seq');
  my $case = member($line, 'case');
  my $output = member($line, 'output');
  my $annotations = defined $output && $JSON->decode($output) eq 'annotations';
  my %registry = map { $_->[0] => $_->[1] } members(member($case, 'registry') // '{}');
  my $validator = eval {
    $PACKAGE->compile(member($case, 'schema'), default_dialect => $dialect,
      resolve_document => sub { $registry{ $_[0] } });
  };
  return qq({"seq":$seq,"errored":true,"context":{"message":) . $JSON->encode(error_text($@)) . '}}' unless $validator;
  my $collector = $annotations ? "${PACKAGE}::ResultsCollector"->new('verbose') : undef;
  my @results;
  for my $test (items(member($case, 'tests') // '[]')) {
    my $instance = member($test, 'instance');
    if (!defined $instance) {
      push @results, '{"errored":true,"context":{"message":"the test has no instance"}}';
      next;
    }
    my $valid = eval { $annotations ? $validator->evaluate_json($instance, $collector) : $validator->is_valid_json($instance) };
    if (my $e = $@) {
      push @results, '{"errored":true,"context":{"message":' . $JSON->encode(error_text($e)) . '}}';
      next;
    }
    push @results, '{"valid":' . ($valid ? 'true' : 'false')
      . ($annotations ? ',"annotations":' . annotations_of($collector) : '') . '}';
  }
  return qq({"seq":$seq,"results":[) . join(',', @results) . ']}';
}

my $started = 0;
my $dialect = 'draft2020-12';
while (my $line = <STDIN>) {
  chomp $line;
  next unless $line =~ /\S/;
  my $cmd = member($line, 'cmd') // fail('A request has no command');
  $cmd = $JSON->decode($cmd);
  my $out;
  if ($cmd eq 'start') {
    my $version = member($line, 'version');
    fail('Unsupported IHOP version') unless defined $version && $version eq '1';
    $started = 1;
    $out = start();
  }
  elsif ($cmd eq 'dialect') {
    fail('Not started') unless $started;
    my $uri = $JSON->decode(member($line, 'dialect') // '""');
    my $found = $DIALECTS{$uri};
    $dialect = $found if $found;
    $out = $found ? '{"ok":true}' : '{"ok":false}';
  }
  elsif ($cmd eq 'run') {
    fail('Not started') unless $started;
    $out = run($line, $dialect);
  }
  elsif ($cmd eq 'stop') {
    fail('Not started') unless $started;
    exit 0;
  }
  else {
    fail('Unknown command');
  }
  print "$out\n";
}

# perl-corvus-json-schema-xs

A [Bowtie](https://github.com/bowtie-json-schema/bowtie) test harness for
[JSON::Schema::Corvus::XS](https://metacpan.org/dist/JSON-Schema-Corvus-XS), the Perl binding to the
corvus-json-schema C library, part of [Corvus.JsonSchema](https://github.com/corvus-dotnet/Corvus.JsonSchema).

Its image is published to `ghcr.io/bowtie-json-schema/perl-corvus-json-schema-xs` and run via
`bowtie run -i perl-corvus-json-schema-xs`.

The image installs the binding and the Alien::CorvusJsonSchema it needs from their CPAN tarballs, as released, which
it copies from `ghcr.io/corvus-dotnet/corvus-json-schema-perl-xs`. Installing the Alien downloads the C library's
release package for the platform and links its static library into the binding. The harness
(`bowtie_corvus_json_schema.pl`) is the pure package's, run with `CORVUS_PACKAGE=JSON::Schema::Corvus::XS`. Dependabot
keeps the image tags in the Dockerfile up to date.

# JSON::Schema::Corvus::XS and the Alien::CorvusJsonSchema it needs, as released to CPAN
# (src-perl/JSON-Schema-Corvus-XS and src-perl/Alien-CorvusJsonSchema in Corvus.JsonSchema): their version is this
# tag, which Dependabot keeps up to date.
FROM ghcr.io/corvus-dotnet/corvus-json-schema-perl-xs:0.1.0 AS dist

FROM perl:5.42.3 AS build
COPY --from=dist /corvus-json-schema /tmp/dist
# The Alien downloads the C library's release package for the platform (checked against the digest it records), and
# the binding links its static library, so nothing of it is needed at run time.
RUN cpanm --notest Alien::Build Alien::Build::MM \
 && cpanm -L /opt/perl5 /tmp/dist/Alien-CorvusJsonSchema-*.tar.gz \
 && PERL5LIB=/opt/perl5/lib/perl5 cpanm -L /opt/perl5 /tmp/dist/JSON-Schema-Corvus-XS-*.tar.gz

FROM perl:5.42.3-slim
COPY --from=build /opt/perl5 /opt/perl5
ENV PERL5LIB=/opt/perl5/lib/perl5 CORVUS_PACKAGE=JSON::Schema::Corvus::XS
COPY bowtie_corvus_json_schema.pl /usr/local/bin/
CMD ["perl", "/usr/local/bin/bowtie_corvus_json_schema.pl"]

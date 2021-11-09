#!/bin/perl

package route;
use strict;
use experimental 'smartmatch';
use Data::Dumper;
use JSON::Parse 'parse_json';
use JSON qw( encode_json );

#
# oc observe routes --type-env-var=T --all-namespaces -- route.pl
#

# action type passed in as env var
my $type = $ENV{'T'};

# only process added routes
exit 0 unless $type ~~ ['Added'];

# route details
my $namespace = $ARGV[0];
my $route = $ARGV[1];
my $content = `oc get route $route -o json -n $namespace | jq .status.ingress[0]`;
my $json = parse_json($content);

# ingress controller details
my $defaultDomain=`oc get ingresscontroller/default -n openshift-ingress-operator -o json | jq .status.domain`;
my $ingressRedHatLabsDomain=`oc get ingresscontroller/redhatlabs -n openshift-ingress-operator -o json | jq .status.domain`;

my $ingresses = {
    'default' => $defaultDomain, 'redhatlabs' => $ingressRedHatLabsDomain
};

# check if router-$routeName matches ingressController
my $expectedRouteDomain = $ingresses->{$json->{'routerName'}};
($expectedRouteDomain) = $expectedRouteDomain =~ /"([^"]*)"/; # strip quotes
if (index ($json->{'host'}, $expectedRouteDomain) != -1) {
    print (">> OK added host $json->{'host'} matches expected router domain: $expectedRouteDomain\n");
} else {
    print (">> EXPECTED host: $json->{'host'} does not match router domain: $expectedRouteDomain\n");
    my $fullroute = `oc get route $route -o json -n $namespace`;
    my $full_json = parse_json($fullroute);
    (my @parts) = split(/\./, $json->{'host'});
    # set the correct hostname
    $full_json->{'spec'}->{'host'} = $parts[0] . "." . $expectedRouteDomain;
    my $apply_me = encode_json($full_json);
    #print Dumper($apply_me);
    # delete and recreate route
    `oc delete route $route -n $namespace`;
    `echo '$apply_me' | oc apply -f-`;
}

use strict;
use warnings;

package Boilerplater::Parser;
use base qw( Parse::RecDescent );

use Boilerplater::Parcel;
use Boilerplater::Type;
use Boilerplater::Type::Primitive;
use Boilerplater::Type::Integer;
use Boilerplater::Type::Float;
use Boilerplater::Type::Void;
use Boilerplater::Type::VAList;
use Boilerplater::Type::Arbitrary;
use Boilerplater::Type::Object;
use Boilerplater::Type::Composite;
use Boilerplater::Variable;
use Boilerplater::DocuComment;
use Boilerplater::Function;
use Boilerplater::Method;
use Boilerplater::Class;
use Boilerplater::CBlock;
use Carp;

our $grammar = <<'END_GRAMMAR';

parcel_definition:
    'parcel' class_name cnick(?) ';'
    { 
        my $parcel = Boilerplater::Parser->new_parcel( \%item );
        Boilerplater::Parser->set_parcel($parcel);
        $parcel;
    }

embed_c:
    '__C__'
    /.*?(?=__END_C__)/s  
    '__END_C__'
    { Boilerplater::CBlock->new( contents => $item[2] ) }

class_declaration:
    docucomment(?)
    exposure_specifier(?) class_modifier(s?) 'class' class_name 
        cnick(?)
        class_extension(?)
        class_attribute(s?)
    '{'
        declaration_statement[
            class  => $item{class_name}, 
            cnick  => $item{'cnick(?)'}[0],
            parent => $item{'class_extension(?)'}[0],
        ](s?)
    '}'
    { Boilerplater::Parser->new_class( \%item, \%arg ) }

class_modifier:
      'inert'
    | 'abstract'
    | 'final'
    { $item[1] }

class_extension:
    'extends' class_name
    { $item[2] }

class_attribute:
    ':' /[a-z]+(?!\w)/
    { $item[2] }

class_name:
    class_name_component ( "::" class_name_component )(s?)
    { join('::', $item[1], @{ $item[2] } ) }

class_name_component:
    /[A-Z]+[A-Z0-9]*[a-z]+[A-Za-z0-9]*(?!\w)/

cnick:
    'cnick'
    /([A-Z][A-Za-z0-9]+)(?!\w)/
    { $1 }

declaration_statement:
      var_declaration_statement[%arg]
    | subroutine_declaration_statement[%arg]
    | <error>

var_declaration_statement:
    exposure_specifier(?) variable_modifier(s?) type declarator ';'
    {
        $return = {
            exposure  => $item[1][0] || 'parcel',
            modifiers => $item[2],
            declared  => Boilerplater::Parser->new_var( \%item, \%arg ),
        };
    }

subroutine_declaration_statement:
    docucomment(?)
    exposure_specifier(?) 
    subroutine_modifier(s?) 
    type 
    declarator 
    param_list 
    ';'
    {
        $return = {
            exposure  => $item[2],
            modifiers => $item[3],
            declared  => Boilerplater::Parser->new_sub( \%item, \%arg ),
        };
    }

param_list:
    '(' 
    param_list_elem(s? /,/)
    (/,\s*.../)(?)
    ')'
    {
        Boilerplater::Parser->new_param_list( $item[2], $item[3][0] ? 1 : 0 );
    }

param_list_elem:
    param_variable assignment(?)
    { [ $item[1], $item[2][0] ] }

param_variable:
    type declarator
    { Boilerplater::Parser->new_var(\%item); }

assignment: 
    '=' scalar_constant
    { $item[2] }

type:
      composite_type
    | simple_type
    { $item[1] }

simple_type:
      object_type
    | primitive_type
    | void_type
    | va_list_type
    | arbitrary_type
    { $item[1] }

composite_type:
    simple_type type_postfix(s)
    { Boilerplater::Parser->new_composite_type(\%item) }

primitive_type:
      c_integer_type
    | chy_integer_type
    | float_type
    { $item[1] }

c_integer_type:
    type_qualifier(s?) c_integer_specifier
    { Boilerplater::Parser->new_integer_type(\%item) }

chy_integer_type:
    type_qualifier(s?) chy_integer_specifier
    { Boilerplater::Parser->new_integer_type(\%item) }

float_type:
    type_qualifier(s?) c_float_specifier
    { Boilerplater::Parser->new_float_type(\%item) }

void_type:
    type_qualifier(s?) void_type_specifier
    { Boilerplater::Parser->new_void_type(\%item) }

va_list_type:
    va_list_type_specifier
    { Boilerplater::Type::VAList->new }

arbitrary_type:
    arbitrary_type_specifier
    { Boilerplater::Parser->new_arbitrary_type(\%item); }

object_type:
    type_qualifier(s?) object_type_specifier '*'
    { Boilerplater::Parser->new_object_type(\%item); }

type_qualifier:
      'const' 
    | 'incremented'
    | 'decremented'

subroutine_modifier:
      'inert'
    | 'inline'
    | 'abstract'
    | 'final'
    { $item[1] }

exposure_specifier:
      'public'
    | 'private'
    | 'parcel'
    | 'local'

variable_modifier:
      'inert'
    { $item[1] }

primitive_type_specifier:
      chy_integer_specifier
    | c_integer_specifier 
    | c_float_specifier 
    { $item[1] }

chy_integer_specifier:
    /(?:chy_)?([iu](8|16|32|64)|bool)_t(?!\w)/

c_integer_specifier:
    /(?:char|int|short|long|size_t)(?!\w)/

c_float_specifier:
    /(?:float|double)(?!\w)/

void_type_specifier:
    /void(?!\w)/

va_list_type_specifier:
    /va_list(?!\w)/

arbitrary_type_specifier:
    /\w+_t(?!\w)/

object_type_specifier:
    /[A-Z]+[A-Z0-9]*[a-z]+[A-Za-z0-9]*(?!\w)/

declarator:
    identifier 
    { $item[1] }

type_postfix:
      '*'
      { '*' }
    | '[' ']'
      { '[]' }
    | '[' constant_expression ']'
      { "[$item[2]]" }

identifier:
    ...!reserved_word /[a-zA-Z_]\w*/x
    { $item[2] }

docucomment:
    /\/\*\*.*?\*\//s
    { Boilerplater::DocuComment->parse($item[1]) }

constant_expression:
      /\d+/
    | /[A-Z_]+/

scalar_constant:
      hex_constant
    | float_constant
    | integer_constant
    | string_literal
    | 'NULL'
    | 'true'
    | 'false'

integer_constant:
    /(?:-\s*)?\d+/
    { $item[1] }

hex_constant:
    /0x[a-fA-F0-9]+/
    { $item[1] }

float_constant:
    /(?:-\s*)?\d+\.\d+/
    { $item[1] }

string_literal: 
    /"(?:[^"\\]|\\.)*"/
    { $item[1] }

reserved_word:
    /(char|const|double|enum|extern|float|int|long|register|signed|sizeof
       |short|inert|struct|typedef|union|unsigned|void)(?!\w)/x
    | chy_integer_specifier

END_GRAMMAR

sub new { return shift->SUPER::new($grammar) }

our $parcel = undef;
sub set_parcel { $parcel = $_[1] }

sub new_integer_type {
    my ( undef, $item ) = @_;
    my $specifier = $item->{c_integer_specifier}
        || $item->{chy_integer_specifier};
    my %args = ( specifier => $specifier );
    $args{$_} = 1 for @{ $item->{'type_qualifier(s?)'} };
    return Boilerplater::Type::Integer->new(%args);
}

sub new_float_type {
    my ( undef, $item ) = @_;
    my %args = ( specifier => $item->{c_float_specifier} );
    $args{$_} = 1 for @{ $item->{'type_qualifier(s?)'} };
    return Boilerplater::Type::Float->new(%args);
}

sub new_void_type {
    my ( undef, $item ) = @_;
    my %args = ( specifier => $item->{void_type_specifier} );
    $args{$_} = 1 for @{ $item->{'type_qualifier(s?)'} };
    return Boilerplater::Type::Void->new(%args);
}

sub new_arbitrary_type {
    my ( undef, $item ) = @_;
    return Boilerplater::Type::Arbitrary->new(
        specifier => $item->{arbitrary_type_specifier},
        parcel    => $parcel,
    );
}

sub new_object_type {
    my ( undef, $item ) = @_;
    my %args = (
        specifier => $item->{object_type_specifier},
        parcel    => $parcel,
    );
    $args{$_} = 1 for @{ $item->{'type_qualifier(s?)'} };
    return Boilerplater::Type::Object->new(%args);
}

sub new_composite_type {
    my ( undef, $item ) = @_;
    my %args = (
        child       => $item->{simple_type},
        indirection => 0,
    );
    for my $postfix ( @{ $item->{'type_postfix(s)'} } ) {
        if ( $postfix =~ /\[/ ) {
            $args{array} ||= '';
            $args{array} .= $postfix;
        }
        elsif ( $postfix eq '*' ) {
            $args{indirection}++;
        }
    }
    return Boilerplater::Type::Composite->new(%args);
}

sub new_var {
    my ( undef, $item, $arg ) = @_;
    my $exposure = $item->{'exposure_specifier(?)'}[0];
    my %args = $exposure ? ( exposure => $exposure ) : ();
    if ($arg) {
        $args{class_name}  = $arg->{class} if $arg->{class};
        $args{class_cnick} = $arg->{cnick} if $arg->{cnick};
    }
    return Boilerplater::Variable->new(
        parcel    => $parcel,
        type      => $item->{type},
        micro_sym => $item->{declarator},
        %args,
    );
}

sub new_param_list {
    my ( undef, $param_list_elems, $variadic ) = @_;
    my @vars = map { $_->[0] } @$param_list_elems;
    my @vals = map { $_->[1] } @$param_list_elems;
    return Boilerplater::ParamList->new(
        variables      => \@vars,
        initial_values => \@vals,
        variadic       => $variadic,
    );
}

sub new_sub {
    my ( undef, $item, $arg ) = @_;
    my $class;
    my $modifiers  = $item->{'subroutine_modifier(s?)'};
    my $docucom    = $item->{'docucomment(?)'}[0];
    my $exposure   = $item->{'exposure_specifier(?)'}[0];
    my $inert      = scalar grep { $_ eq 'inert' } @$modifiers;
    my %extra_args = $exposure ? ( exposure => $exposure ) : ();

    if ($inert) {
        $class = 'Boilerplater::Function';
        $extra_args{micro_sym} = $item->{declarator};
        $extra_args{inline} = scalar grep { $_ eq 'inline' } @$modifiers;
    }
    else {
        $class = 'Boilerplater::Method';
        $extra_args{macro_sym} = $item->{declarator};
        $extra_args{abstract} = scalar grep { $_ eq 'abstract' } @$modifiers;
        $extra_args{final}    = scalar grep { $_ eq 'final' } @$modifiers;
    }

    return $class->new(
        parcel      => $parcel,
        docucomment => $docucom,
        class_name  => $arg->{class},
        class_cnick => $arg->{cnick},
        return_type => $item->{type},
        param_list  => $item->{param_list},
        %extra_args,
    );
}

sub new_class {
    my ( undef, $item, $arg ) = @_;
    my ( @member_vars, @inert_vars, @functions, @methods );
    my $source_class = $arg->{source_class} || $item->{class_name};
    my %class_modifiers
        = map { ( $_ => 1 ) } @{ $item->{'class_modifier(s?)'} };
    my %class_attributes
        = map { ( $_ => 1 ) } @{ $item->{'class_attribute(s?)'} };

    for my $declaration ( @{ $item->{'declaration_statement(s?)'} } ) {
        my $declared  = $declaration->{declared};
        my $exposure  = $declaration->{exposure};
        my $modifiers = $declaration->{modifiers};
        my $inert     = ( scalar grep {/inert/} @$modifiers ) ? 1 : 0;
        my $subs      = $inert ? \@functions : \@methods;
        my $vars      = $inert ? \@inert_vars : \@member_vars;

        if ( $declared->isa('Boilerplater::Variable') ) {
            push @$vars, $declared;
        }
        else {
            push @$subs, $declared;
        }
    }

    return Boilerplater::Class->create(
        parcel            => $parcel,
        class_name        => $item->{class_name},
        cnick             => $item->{'cnick(?)'}[0],
        parent_class_name => $item->{'class_extension(?)'}[0],
        member_vars       => \@member_vars,
        functions         => \@functions,
        methods           => \@methods,
        inert_vars        => \@inert_vars,
        docucomment       => $item->{'docucomment(?)'}[0],
        source_class      => $source_class,
        inert             => $class_modifiers{inert},
        final             => $class_modifiers{final},
        attributes        => \%class_attributes,
    );
}

sub new_parcel {
    my ( undef, $item ) = @_;
    Boilerplater::Parcel->singleton(
        name  => $item->{class_name},
        cnick => $item->{'cnick(?)'}[0],
    );
}

1;

__END__

__POD__

=head1 NAME

Boilerplater::Parser - Parse Boilerplater header files.

=head1 SYNOPSIS

     my $class_def = $parser->class($class_text);

=head1 DESCRIPTION

Boilerplater::Parser is a combined lexer/parser which parses .bp code.  It is
not at all strict, as it relies heavily on the C parser to pick up errors such
as misspelled type names.

=head1 COPYRIGHT AND LICENSE

    /**
     * Copyright 2009 The Apache Software Foundation
     *
     * Licensed under the Apache License, Version 2.0 (the "License");
     * you may not use this file except in compliance with the License.
     * You may obtain a copy of the License at
     *
     *     http://www.apache.org/licenses/LICENSE-2.0
     *
     * Unless required by applicable law or agreed to in writing, software
     * distributed under the License is distributed on an "AS IS" BASIS,
     * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
     * implied.  See the License for the specific language governing
     * permissions and limitations under the License.
     */

=cut


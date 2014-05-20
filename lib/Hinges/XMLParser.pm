use v6;

use Hinges::Stream;

grammar Hinges::XMLGrammar {
    regex TOP { ^ <doctype>? <xmlcontent>* $ };

    token xmlcontent {
        || <element>
        || <textnode>
    };

    token element {
        '<' <name=ident> <attrs> '/>'
        ||
        '<' <name=ident> <attrs> '>'
        <xmlcontent>+
        '</' $<name> '>'
    }

    token attrs { <attr>* }
    rule attr { $<name>=[<.ident>[':'<.ident>]?] '=' '"'
                $<value>=[<-["]>+] '"' } # '
    token ident { <+alnum + [\-]>+ }

    regex textnode { <-[<]>+ {*} }

    token doctype { '<!DOCTYPE' <name=ident> <externalId> '>' }
    token externalId { 'PUBLIC' <pubid> <system> }
    token pubid  { '"' $<name>=[<-["]>+] '"' }
    token system { '"' $<name>=[<-["]>+] '"' }
}

class Hinges::XMLParser {
    has $!text;

    method new($text, $filename?, $encoding?) {
        return self.bless(:$text);
    }

    submethod BUILD(:$!text) { }

    submethod make-events(Match $m, $text) {
        return () unless $m<xmlcontent>;
        my @events;
        for @($m<doctype> // []) -> $d {
            push @events, [Hinges::StreamEventKind::doctype, *, *];
        }
        for @($m<xmlcontent>) -> $part {
            if $part<element> -> $e {
                my $data = [~$e<name>,
                            [map {; ~.<name> => convert-entities(~.<value>) },
                                 $e<attrs><attr> ?? $e<attrs><attr>.list !! ()]
                           ];
                push @events, [Hinges::StreamEventKind::start, $data, *],
                              self.make-events($e, $text),
                              [Hinges::StreamEventKind::end, ~$e<name>, *];
            }
            elsif $part<textnode> -> $t {
                my $line-num = +$text.substr(0, $t.from).comb(/\n/) + 1;
                my $pos = [Nil, $line-num, $t.from];
                my $tt = convert-entities(~$t);
                push @events, [Hinges::StreamEventKind::text, $tt, $pos];
            }
        }
        return @events;
    }

    sub convert-entities($text) {
        die "Unrecognized entity $0"
            if $text ~~ / ('&' <!before nbsp> \w+ ';') /;
        $text.subst('&nbsp;', "\x[a0]", :g)
    }

    # RAKUDO: https://trac.parrot.org/parrot/ticket/536 makes the method
    #         override the global 'list' sub if we call it 'list'
    method llist() {
        Hinges::XMLGrammar.parse($!text) or die "Couldn't parse $!text";
        my @actions = self.make-events($/, $!text);
        return @actions;
    }
}

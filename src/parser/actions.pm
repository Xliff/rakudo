# $Id$
#
# Copyright (C) 2007-2008, The Perl Foundation.

class Perl6::Grammar::Actions ;

method TOP($/) {
    my $past := $( $<statement_block> );
    $past.blocktype('declaration');

    # Attach any initialization code.
    our $?INIT;
    if defined( $?INIT ) {
        $?INIT.unshift(
            PAST::Var.new(
                :name('$def'),
                :scope('lexical'),
                :isdecl(1)
            )
        );
        $?INIT.blocktype('declaration');
        $?INIT.pirflags(':init :load');
        $past.unshift( $?INIT );
        $?INIT := PAST::Block.new(); # For the next eval.
    }

    make $past;
}


method statement_block($/, $key) {
    our $?BLOCK;
    our @?BLOCK;
    our $?BLOCK_SIGNATURED;
    ##  when entering a block, use any $?BLOCK_SIGNATURED if it exists,
    ##  otherwise create an empty block with an empty first child to
    ##  hold any parameters we might encounter inside the block.
    if $key eq 'open' {
        if $?BLOCK_SIGNATURED {
            $?BLOCK := $?BLOCK_SIGNATURED;
            $?BLOCK_SIGNATURED := 0;
            $?BLOCK.symbol('___HAVE_A_SIGNATURE', :scope('lexical'));
        }
        else {
            $?BLOCK := PAST::Block.new( PAST::Stmts.new(), :node($/));
        }
        @?BLOCK.unshift($?BLOCK);
        my $init := $?BLOCK[0];
        unless $?BLOCK.symbol('$_') {
            $init.push( PAST::Var.new( :name('$_'), :isdecl(1) ) );
            $?BLOCK.symbol( '$_', :scope('lexical') );
        }
        unless $?BLOCK.symbol('$/') {
            $init.push( PAST::Var.new( :name('$/'), :isdecl(1) ) );
            $?BLOCK.symbol( '$/', :scope('lexical') );
            $init.push(
                PAST::Op.new(
                    :inline(
                          "    %r = getinterp\n"
                        ~ "    %r = %r['lexpad';1]\n"
                        ~ "    if null %r goto no_match_to_copy\n"
                        ~ "    %r = %r['$/']\n"
                        ~ "    store_lex '$/', %r\n"
                        ~ "  no_match_to_copy:\n"
                    )
                )
            );
        }
        unless $?BLOCK.symbol('$!') {
            $init.push( PAST::Var.new( :name('$!'), :isdecl(1) ) );
            $?BLOCK.symbol( '$!', :scope('lexical') ); }
    }
    if $key eq 'close' {
        my $past := @?BLOCK.shift();
        $?BLOCK := @?BLOCK[0];
        if $past.symbol('___MAYBE_NEED_TOPIC_FIXUP') && !$past.symbol('___HAVE_A_SIGNATURE') {
            if $past[0][0].name() ne '$_' { $/.panic('$_ handling is very poor right now.') };
            $past.symbol('$_', :scope('lexical'));
            $past[0][0].scope('parameter');
            $past[0][0].isdecl(0);
        }
        $past.push($($<statementlist>));
        make $past;
    }
}


method block($/) {
    make $( $<statement_block> );
}


method statementlist($/) {
    my $past := PAST::Stmts.new( :node($/) );
    for $<statement> {
        $past.push( $($_) );
    }
    make $past;
}


method statement($/, $key) {
    my $past;
    if $key eq 'statement_control' {
        $past := $( $<statement_control> );
    }
    else {
        my $expr := $( $<expr> );
        if $expr.WHAT() eq 'Block' && !$expr.blocktype() {
            $expr.blocktype('immediate');
        }
        if $key eq 'statement_mod_cond' {
            $past := $( $<statement_mod_cond> );
            $past.push( $expr );
            if $<sml> {
                $expr := $past;
                $key := 'statement_mod_loop';
                $<statement_mod_loop> := $<sml>[0];
            }
        }
        if $key eq 'statement_mod_loop' {
            my $mod := $( $<statement_mod_loop> );
            if $<statement_mod_loop><sym> eq 'for' {
                my $loop :=  PAST::Block.new(
                    PAST::Stmts.new(
                        PAST::Var.new(
                            :name('$_'),
                            :scope('parameter'),
                            :viviself('Undef')
                        ),
                        $expr
                    ),
                    :node( $/ )
                );
                $loop.symbol( '$_', :scope('lexical') );
                $mod.push($loop);
                $past := PAST::Stmts.new( $mod, :node($/) );
            }
            else {
                $mod.push( $expr );
                $past := PAST::Block.new( $mod, :blocktype('immediate'), :node($/) );
            }
        }
        else {
            $past := $expr;
        }
    }
    make $past;
}


method statement_control($/, $key) {
    make $( $/{$key} );
}


method if_statement($/) {
    my $count := +$<EXPR> - 1;
    my $expr  := $( $<EXPR>[$count] );
    my $then  := $( $<block>[$count] );
    $then.blocktype('immediate');
    my $past := PAST::Op.new(
        $expr, $then,
        :pasttype('if'),
        :node( $/ )
    );
    if $<else> {
        my $else := $( $<else>[0] );
        $else.blocktype('immediate');
        $past.push( $else );
    }
    while $count != 0 {
        $count := $count - 1;
        $expr  := $( $<EXPR>[$count] );
        $then  := $( $<block>[$count] );
        $then.blocktype('immediate');
        $past  := PAST::Op.new(
            $expr, $then, $past,
            :pasttype('if'),
            :node( $/ )
        );
    }
    make $past;
}


method unless_statement($/) {
    my $then := $( $<block> );
    $then.blocktype('immediate');
    my $past := PAST::Op.new(
        $( $<EXPR> ), $then,
        :pasttype('unless'),
        :node( $/ )
    );
    make $past;
}


method while_statement($/) {
    my $cond  := $( $<EXPR> );
    my $block := $( $<block> );
    $block.blocktype('immediate');
    make PAST::Op.new( $cond, $block, :pasttype(~$<sym>), :node($/) );
}

method repeat_statement($/) {
    my $cond  := $( $<EXPR> );
    my $block := $( $<block> );
    $block.blocktype('immediate');
    # pasttype is 'repeat_while' or 'repeat_until'
    my $pasttype := 'repeat_' ~ ~$<loop>;
    make PAST::Op.new( $cond, $block, :pasttype($pasttype), :node($/) );
}

method given_statement($/) {
    my $past := $( $<block> );
    $past.blocktype('immediate');

    # Node to assign expression to $_.
    my $expr := $( $<EXPR> );
    my $assign := PAST::Op.new(
        :name('infix::='),
        :pasttype('bind'),
        :node($/)
    );
    $assign.push( PAST::Var.new( :node($/), :name('$_'), :scope('lexical') ) );
    $assign.push( $expr );

    # Put as first instruction in block (but after .lex $_).
    my $statements := $past[1];
    $statements.unshift( $assign );

    make $past;
}

method when_statement($/) {
    my $block := $( $<block> );
    $block.blocktype('immediate');

    # XXX TODO: push a control exception throw onto the end of the block so we
    # exit the innermost block in which $_ was set.

    # Invoke smartmatch of the expression.
    my $expr := $( $<EXPR> );
    my $match_past := PAST::Op.new(
        :name('infix:~~'),
        :pasttype('call'),
        :node($/)
    );
    $match_past.push(
        PAST::Var.new( :node($/), :name('$_'), :scope('lexical') )
    );
    $match_past.push( $expr );

    # Use the smartmatch result as the condition.
    my $past := PAST::Op.new(
        $match_past, $block,
        :pasttype('if'),
        :node( $/ )
    );
    make $past;
}

method default_statement($/) {
    # Always executed if reached, so just produce the block.
    my $past := $( $<block> );
    $past.blocktype('immediate');
    make $past;
}

method loop_statement($/) {
    if $<eee> {
        my $init := $( $<e1>[0] );
        my $cond := $( $<e2>[0] );
        my $tail := $( $<e3>[0] );
        my $block := $( $<block> );
        $block.blocktype('immediate');

        my $loop := PAST::Stmts.new(
            $init,
            PAST::Op.new(
                $cond,
                PAST::Stmts.new($block, $tail),
                :pasttype('while'),
                :node($/)
            ),
            :node($/)
        );
        make $loop;
    }
    else {
        my $cond  := PAST::Val.new( :value( 1 ) );
        my $block := $( $<block> );
        $block.blocktype('immediate');
        make PAST::Op.new( $cond, $block, :pasttype('while'), :node($/) );
    }
}

method for_statement($/) {
    my $block := $( $<pblock> );
    $block.blocktype('declaration');
    my $past := PAST::Op.new(
        $( $<EXPR> ),
        $block,
        :pasttype($<sym>),
        :node( $/ )
    );
    make $past;
}

method pblock($/) {
    my $block := $( $<block> );
    make $block;
}

method use_statement($/) {
    my $name := ~$<name>;
    my $past;
    if $name eq 'v6' || $name eq 'lib' {
        $past := PAST::Stmts.new( :node($/) );
    }
    else {
        $past := PAST::Op.new(
            PAST::Val.new( :value($name) ),
            :name('use'),
            :pasttype('call'),
            :node( $/ )
        );
    }
    make $past;
}

method begin_statement($/) {
    my $past := $( $<block> );
    $past.blocktype('declaration');
    my $sub := PAST::Compiler.compile( $past );
    $sub();
    # XXX - should emit BEGIN side-effects, and do a proper return()
    make PAST::Block.new();
}

method end_statement($/) {
    my $past := $( $<block> );
    $past.blocktype('declaration');
    my $sub := PAST::Compiler.compile( $past );
    PIR q<  $P0 = get_hll_global ['Perl6'], '@?END_BLOCKS' >;
    PIR q<  $P1 = find_lex '$sub' >;
    PIR q<  push $P0, $P1 >;
    make $past;
}

method statement_mod_loop($/) {
    my $expr := $( $<EXPR> );
    if ~$<sym> eq 'given' {
        my $assign := PAST::Op.new(
            :name('infix::='),
            :pasttype('bind'),
            :node($/)
        );
        $assign.push(
            PAST::Var.new( :node($/), :name('$_'), :scope('lexical') )
        );
        $assign.push( $expr );

        my $past := PAST::Stmts.new( $assign, :node($/) );
        make $past;
    }
    elsif ~$<sym> eq 'for' {
        my $past := PAST::Op.new(
            $expr,
            :pasttype($<sym>),
            :node( $/ )
        );
        make $past;
    }
    else {
        make PAST::Op.new(
            $expr,
            :pasttype( ~$<sym> ),
            :node( $/ )
        );
    }
}

method statement_mod_cond($/) {
    if ~$<sym> eq 'when' {
        my $expr := $( $<EXPR> );
        my $match_past := PAST::Op.new(
            :name('infix:~~'),
            :pasttype('call'),
            :node($/)
        );
        $match_past.push(
            PAST::Var.new( :node($/), :name('$_'), :scope('lexical') )
        );
        $match_past.push( $expr );

        my $past := PAST::Op.new(
            $match_past,
            :pasttype('if'),
            :node( $/ )
        );
        make $past;
    }
    else {
        make PAST::Op.new(
            $( $<EXPR> ),
            :pasttype( ~$<sym> ),
            :node( $/ )
        );
    }
}


method statement_prefix($/) {
    my $past := $($<statement>);
    my $sym := ~$<sym>;
    if $sym eq 'do' {
        # fall through, just use the statement itself
    }
    ## after the code in the try block is executed, bind $! to Undef,
    ## and set up the code to catch an exception, in case one is thrown
    elsif $sym eq 'try' {
        ##  Set up code to execute <statement> as a try node, and
        ##  set $! to Undef if successful.
        my $exitpir  := "    new %r, 'Undef'\n    store_lex '$!', %r";
        my $try := PAST::Stmts.new(
            $past,
            PAST::Op.new( :inline( $exitpir ) )
        );
        $past := PAST::Op.new( $try, :pasttype('try') );

        ##  Add a catch node to the try op that captures the
        ##  exception object into $!.
        my $catchpir := "    .get_results (%r, $S0)\n    store_lex '$!', %r";
        $past.push( PAST::Op.new( :inline( $catchpir ) ) );
    }
    else {
        $/.panic( $sym ~ ' not implemented');
    }
    make $past;
}


method plurality_declarator($/) {
    my $past := $( $<routine_declarator> );
    if $<sym> eq 'multi' {
        our $?PARAM_TYPE_CHECK;
        my @check_list := @($?PARAM_TYPE_CHECK);

        # Go over the parameters and build multi-sig.
        my $pirflags := ~ $past.pirflags();
        $pirflags := $pirflags ~ ' :multi(';
        my $arity := +@check_list;
        my $count := 0;
        while $count != $arity {
            # How many types do we have?
            my $checks := @check_list[$count];
            my $num_checks := +@($checks);
            if $num_checks == 0 {
                # XXX Should be Any, once type hierarchy is fixed up.
                $pirflags := $pirflags ~ '_';
            }
            elsif $num_checks == 1 {
                # At the moment, can only handle a named check.
                my $check_code := $checks[0];
                if $check_code.WHAT() eq 'Op'
                        && $check_code[0].WHAT() eq 'Var' {
                    $pirflags := $pirflags
                        ~ '\'' ~ $check_code[0].name() ~ '\'';
                }
                else {
                    $/.panic(
                        'Can only use type names in a multi,'
                        ~ ' not anonymous constraints.'
                    );
                }
            }
            else {
                $/.panic(
                    'Cannot have more than one type constraint'
                    ~ ' on a parameter in a multi yet.'
                );
            }

            # Comma separator if needed.
            $count := $count + 1;
            if $count != $arity {
                $pirflags := $pirflags ~ ', ';
            }
        }
        $pirflags := $pirflags ~ ')';
        $past.pirflags($pirflags);
    }
    make $past;
}


method routine_declarator($/, $key) {
    if $key eq 'sub' {
        my $past := $($<routine_def>);
        $past.blocktype('declaration');
        $past.node($/);
        make $past;
    }
    elsif $key eq 'method' {
        my $past := $($<method_def>);
        $past.blocktype('declaration');
        $past.pirflags(':method');
        $past.node($/);
        make $past;
    }
}


method routine_def($/) {
    my $past := $( $<block> );
    if $<ident> {
        $past.name( ~$<ident>[0] );
        our $?BLOCK;
        $?BLOCK.symbol(~$<ident>[0], :scope('package'));
    }
    make $past;
}

method method_def($/) {
    my $past := $( $<block> );
    if $<ident> {
        $past.name( ~$<ident>[0] );
    }
    make $past;
}

method signature($/) {
    my $params := PAST::Stmts.new( :node($/) );
    my $type_check := PAST::Stmts.new( :node($/) );
    my $past := PAST::Block.new( $params, :blocktype('declaration') );
    for $/[0] {
        # Add parameter declaration.
        my $parameter := $($_<parameter>);
        $past.symbol($parameter.name(), :scope('lexical'));
        $params.push($parameter);

        # Add any type check that is needed. The scheme for this: $type_check
        # is a statement block. We create a block for each parameter, which
        # will be empty if there are no constraints for that parameter. This
        # is so we can later generate a multi-sig from it.
        my $cur_param_types := PAST::Stmts.new();
        if $_<parameter><type_constraint> {
            for $_<parameter><type_constraint> {
                # Just a type name?
                if $_<typename> {
                    $cur_param_types.push(
                        PAST::Op.new(
                            :pasttype('call'),
                            :name('!TYPECHECKPARAM'),
                            $( $_<typename> ),
                            PAST::Var.new(
                                :name($parameter.name()),
                                :scope('lexical')
                            )
                        )
                    );
                }
                else {
                    # We need a block containing the constraint condition.
                    my $past := $( $_<EXPR> );
                    if $past.WHAT() ne 'Block' {
                        # Make block with the expression as its contents.
                        $past := PAST::Block.new(
                            PAST::Stmts.new(),
                            PAST::Stmts.new( $past )
                        );
                    }

                    # Make sure it has a parameter.
                    my $param;
                    my $dollar_underscore;
                    for @($past[0]) {
                        if $_.WHAT() eq 'Var' {
                            if $_.scope() eq 'parameter' {
                                $param := $_;
                            }
                            elsif $_.name() eq '$_' {
                                $dollar_underscore := $_;
                            }
                        }
                    }
                    unless $param {
                        if $dollar_underscore {
                            $dollar_underscore.scope('parameter');
                            $param := $dollar_underscore;
                        }
                        else {
                            $param := PAST::Var.new(
                                :name('$_'),
                                :scope('parameter')
                            );
                            $past[0].push($param);
                        }
                    }

                    # Now we'll just pass this block to the type checker,
                    # since smart-matching a block invokes it.
                    $cur_param_types.push(
                        PAST::Op.new(
                            :pasttype('call'),
                            :name('!TYPECHECKPARAM'),
                            $past,
                            PAST::Var.new(
                                :name($parameter.name()),
                                :scope('lexical')
                            )
                        )
                    );
                }
            }
        }

        $type_check.push($cur_param_types);
    }
    $past.arity( +$/[0] );
    our $?BLOCK_SIGNATURED := $past;
    our $?PARAM_TYPE_CHECK := $type_check;
    $past.push($type_check);
    make $past;
}


method parameter($/) {
    my $past := $( $<param_var> );
    my $sigil := $<param_var><sigil>;
    if $<quant> eq '*' {
        $past.slurpy( $sigil eq '@' || $sigil eq '%' );
        $past.named( $sigil eq '%' );
    }
    else {
        if $<named> eq ':' {          # named
            $past.named(~$<param_var><ident>);
            if $<quant> ne '!' {      #  required (optional is default)
                $past.viviself('Undef');
            }
        }
        else {                        # positional
            if $<quant> eq '?' {      #  optional (required is default)
                $past.viviself('Undef');
            }
        }
    }
    if $<default_value> {
        if $<quant> eq '!' {
            $/.panic("Can't put a default on a required parameter");
        }
        if $<quant> eq '*' {
            $/.panic("Can't put a default on a slurpy parameter");
        }
        $past.viviself( $( $<default_value>[0]<EXPR> ) );
    }
    make $past;
}


method param_var($/) {
    make PAST::Var.new(
        :name(~$/),
        :scope('parameter'),
        :node($/)
    );
}


method special_variable($/) {
    make PAST::Var.new( :node($/), :name(~$/), :scope('lexical') );
}


method term($/, $key) {
    my $past;
    if $key eq '*' {
        # Whatever.
        $past := PAST::Op.new(
            :pasttype('callmethod'),
            :name('new'),
            :node($/),
            :lvalue(1),
            PAST::Var.new(
                :name('Whatever'),
                :scope('package'),
                :node($/)
            )
        );
    }
    else {
        $past := $( $/{$key} );
    }

    if $<postfix> {
        for $<postfix> {
            my $term := $past;
            $past := $($_);

            # Check if it's an indirect call.
            if $_<dotty><methodop><variable> {
                # What to call supplied; need to put the invocant second.
                my $meth := $past[0];
                $past[0] := $term;
                $past.unshift($meth);
            }
            elsif $_<dotty><methodop><quote> {
                # First child is something that we evaluate to get the
                # name. Replace it with PIR to call find_method on it.
                my $meth_name := $past[0];
                $past[0] := $term;
                $past.unshift(
                    PAST::Op.new(
                        :inline("$S1000 = %1\n%r = find_method %0, $S1000\n"),
                        $term,
                        $meth_name
                    )
                );
            }
            else {
                $past.unshift($term);
            }
        }
    }
    make $past;
}


method postfix($/, $key) {
    make $( $/{$key} );
}


method dotty($/, $key) {
    my $past := $( $<methodop> );

    if $key eq '.' {
        # Just a normal method call; nothing to do.
    }
    elsif $key eq '!' {
        # Private method call. Need to put ! on the start of the name.
        $/.panic('Private method calls not yet implemented.')
    }
    elsif $key eq '.*' {
        $/.panic($key ~ ' method calls not yet implemented.');
    }

    make $past;
}


method methodop($/, $key) {
    my $past;

    if $key eq 'null' {
        $past := PAST::Op.new();
    }
    else {
        $past := PAST::Op.new();
        my $args := $( $/{$key} );
        process_arguments($past, $args);
    }
    $past.pasttype('callmethod');
    $past.node($/);

    if $<name> {
        $past.name(~$<name><ident>[0]);
    }
    elsif $<variable> {
        $past.unshift( $( $<variable> ) );
    }
    else {
        $past.unshift( $( $<quote> ) );
    }

    make $past;
}

method postcircumfix($/, $key) {
    my $past;
    if $key eq '[ ]' {
        # If we got a comma separated list, we'll pass that along as a List,
        # so we can do slices.
        my $semilist := $( $<semilist> );
        if $( $<semilist><EXPR>[0] ).name() eq 'infix:,' {
            $semilist.pasttype('call');
            $semilist.name('list');
        }
        else {
            $semilist := $semilist[0];
        }
        $past := PAST::Var.new(
            $semilist,
            :scope('keyed'),
            :vivibase('List'),
            :viviself('Undef'),
            :node( $/ )
        );
    }
    elsif $key eq '( )' {
        my $semilist := $( $<semilist> );
        $past := PAST::Op.new( :node($/), :pasttype('call') );
        process_arguments($past, $semilist);
    }
    elsif $key eq '{ }' {
        # If we got a comma separated list, we'll pass that along as a List,
        # so we can do slices.
        my $semilist := $( $<semilist> );
        if $( $<semilist><EXPR>[0] ).name() eq 'infix:,' {
            $semilist.pasttype('call');
            $semilist.name('list');
        }
        else {
            $semilist := $semilist[0];
        }
        $past := PAST::Var.new(
            $semilist,
            :scope('keyed'),
            :vivibase('Perl6Hash'),
            :viviself('Undef'),
            :node( $/ )
        );
    }
    elsif $key eq '< >' {
        $past := PAST::Var.new(
            $( $<quote_expression> ),
            :scope('keyed'),
            :vivibase('Perl6Hash'),
            :viviself('Undef'),
            :node( $/ )
        );
    }
    else {
        $/.panic("postcircumfix " ~ $key ~ " not yet implemented");
    }
    make $past;
}


method noun($/, $key) {
    my $past;
    if $key eq 'self' {
        $past := PAST::Stmts.new( PAST::Op.new( :inline('%r = self'), :node( $/ ) ) );
    }
    elsif $key eq 'undef' {
        $past := PAST::Op.new(
            :pasttype('callmethod'),
            :name('new'),
            :node($/),
            PAST::Var.new(
                :name('Failure'),
                :scope('package')
            )
        );
    }
    elsif $key eq 'dotty' {
        # Call on $_.
        $past := $( $/{$key} );
        $past.unshift(PAST::Var.new(
            :name('$_'),
            :scope('lexical'),
            :node($/)
        ));
    }
    else {
        $past := $( $/{$key} );
    }
    make $past;
}


method package_declarator($/, $key) {
    our $?INIT;
    our $?CLASS;
    our @?CLASS;
    our $?ROLE;
    our @?ROLE;
    our $?PACKAGE;
    our @?PACKAGE;
    our $?GRAMMAR;
    our @?GRAMMAR;
    our $?NS;

    if $key eq 'open' {
        # Store the current namespace.
        $?NS := $<name><ident>;

        # Start of the block; if it's a class or role, need to make $?CLASS or
        # $?ROLE available for storing current definition in.
        if $<sym> eq 'class' || $<sym> eq 'role' || $<sym> eq 'grammar' {
            my $decl_past := PAST::Stmts.new();

            # If it's a class...
            if $<sym> eq 'class' {
                # Call method to create the class.
                $decl_past.push(
                    PAST::Op.new(
                        :pasttype('bind'),
                        PAST::Var.new(
                            :name('$def'),
                            :scope('lexical')
                        ),
                        PAST::Op.new(
                            :pasttype('callmethod'),
                            :name('!keyword_class'),
                            PAST::Var.new(
                                :name('Perl6Object'),
                                :scope('package')
                            ),
                            PAST::Val.new( :value(~$<name>) )
                        )
                    )
                );

                # Put current class, if any, on @?CLASS list so we can handle
                # nested classes.
                @?CLASS.unshift( $?CLASS );
                $?CLASS := $decl_past;

                # Set it as the current package.
                @?PACKAGE.unshift( $?PACKAGE );
                $?PACKAGE := $?CLASS;
            }

            # If it's a role...
            elsif $<sym> eq 'role' {
                # Call method to create the role.
                $decl_past.push(
                    PAST::Op.new(
                        :pasttype('bind'),
                        PAST::Var.new(
                            :name('$def'),
                            :scope('lexical')
                        ),
                        PAST::Op.new(
                            :pasttype('callmethod'),
                            :name('!keyword_role'),
                            PAST::Var.new(
                                :name('Perl6Object'),
                                :scope('package')
                            ),
                            PAST::Val.new( :value(~$<name>) )
                        )
                    )
                );

                # Put current role, if any, on @?ROLE list so we can handle
                # nested roles.
                @?ROLE.unshift( $?ROLE );
                $?ROLE := $decl_past;

                # Set it as the current package.
                @?PACKAGE.unshift( $?PACKAGE );
                $?PACKAGE := $?ROLE;
            }

            # If it's a grammar...
            elsif $<sym> eq 'grammar' {
                # Create class for the grammar - a subclass of PGE::Grammar by
                # default.
                $decl_past.push(
                    PAST::Op.new(
                        :pasttype('bind'),
                        PAST::Var.new(
                            :name('$def'),
                            :scope('lexical')
                        ),
                        PAST::Op.new(
                            :pasttype('callmethod'),
                            :name('!keyword_grammar'),
                            PAST::Var.new(
                                :name('Perl6Object'),
                                :scope('package')
                            ),
                            PAST::Val.new( :value(~$<name>) )
                        )
                    )
                );

                # Put current grammar, if any, on @?GRAMMAR list so we can
                # handle nested grammars.
                @?GRAMMAR.unshift( $?GRAMMAR );
                $?GRAMMAR := $decl_past;

                # Set it as the current package.
                @?PACKAGE.unshift( $?PACKAGE );
                $?PACKAGE := $?GRAMMAR;
            }

            # Apply any traits and do any roles.
            my $does_pir;
            for $<trait_or_does> {
                if $_<trait> {
                    # Apply the trait.
                    if $_<trait><trait_auxiliary><sym> eq 'is' {
                        $?PACKAGE.push(
                            PAST::Op.new(
                                :pasttype('call'),
                                :name('trait_auxiliary:is'),
                                PAST::Var.new(
                                    :name(~$_<trait><trait_auxiliary><ident>),
                                    :scope('package')
                                ),
                                PAST::Var.new(
                                    :name('$def'),
                                    :scope('lexical')
                                )
                            )
                        );
                    }
                }
                elsif $_<sym> eq 'does' {
                    # Role.
                    $?PACKAGE.push(
                        PAST::Op.new(
                            :pasttype('callmethod'),
                            :name('!keyword_does'),
                            PAST::Var.new(
                                :name('Perl6Object'),
                                :scope('package')
                            ),
                            PAST::Var.new(
                                :name('$def'),
                                :scope('lexical')
                            ),
                            PAST::Val.new( :value(~$_<name>) )
                        )
                    );
                }
            }
        }
        else {
            # It's a module. We need a way to mark that the current package is
            # not a role or a class, so we put the current one on the array and
            # set $?PACKAGE to undef.
            @?PACKAGE.unshift( $?PACKAGE );
            $?PACKAGE := undef;
        }
    }
    else {
        my $past := $( $/{$key} );

        # Declare the namespace and that this is something we do
        # "on load".
        $past.namespace($<name><ident>);
        $past.blocktype('declaration');
        $past.pirflags(':init :load');

        if $<sym> eq 'class' {
            # Make proto-object.
            $?CLASS.push(
                PAST::Op.new(
                    :pasttype('call'),
                    PAST::Var.new(
                        :scope('package'),
                        :namespace('Perl6Object'),
                        :name('make_proto')
                    ),
                    PAST::Var.new(
                        :scope('lexical'),
                        :name('$def')
                    ),
                    PAST::Val.new( :value(~$<name>) )
                )
            );

            # Attatch any class initialization code to the init code;
            # note that we skip blocks, which are method accessors that
            # we want to put under this block so they get the correct
            # namespace.
            unless defined( $?INIT ) {
                $?INIT := PAST::Block.new();
            }
            for @( $?CLASS ) {
                if $_.WHAT() eq 'Block' {
                    $past.push( $_ );
                }
                else {
                    $?INIT.push( $_ );
                }
            }

            # Restore outer class.
            $?CLASS := @?CLASS.shift();
        }
        elsif $<sym> eq 'role' {
            # Attatch role declaration to the init code.
            unless defined( $?INIT ) {
                $?INIT := PAST::Block.new();
            }
            $?INIT.push( $?ROLE );

            # Restore outer role.
            $?ROLE := @?ROLE.shift();
        }
        elsif $<sym> eq 'grammar' {
            # Make proto-object.
            $?GRAMMAR.push(
                PAST::Op.new(
                    :pasttype('call'),
                    PAST::Var.new(
                        :scope('package'),
                        :namespace('Perl6Object'),
                        :name('make_grammar_proto')
                    ),
                    PAST::Var.new(
                        :scope('lexical'),
                        :name('$def')
                    ),
                    PAST::Val.new( :value(~$<name>) )
                )
            );

            # Attatch grammar declaration to the init code.
            unless defined( $?INIT ) {
                $?INIT := PAST::Block.new();
            }
            $?INIT.push( $?GRAMMAR );

            # Restore outer grammar.
            $?GRAMMAR := @?GRAMMAR.shift();
        }

        # Restore outer package.
        $?PACKAGE := @?PACKAGE.shift();

        make $past;
    }
}


method variable_decl($/) {
    my $past := $( $<variable> );
    if $<trait> {
        for $<trait> {
            my $trait := $_;
            if $trait<trait_auxiliary> {
                my $aux := $trait<trait_auxiliary>;
                my $sym := $aux<sym>;
                if $sym eq 'is' {
                    if $aux<postcircumfix> {
                        $/.panic("'" ~ ~$trait ~ "' not implemented");
                    }
                    else {
                        $past.viviself($aux<ident>);
                    }
                }
                else {
                    $/.panic("'" ~ $sym ~ "' not implemented");
                }
            }
            elsif $trait<trait_verb> {
                my $verb := $trait<trait_verb>;
                my $sym := $verb<sym>;
                if $sym ne 'handles' {
                    $/.panic("'" ~ $sym ~ "' not implemented");
                }
            }
        }
    }

    make $past;
}


method scoped($/) {
    my $past;

    # Variable declaration?
    if $<variable_decl> {
        $past := $( $<variable_decl> );

        # Do we have any type names?
        if $<typename> {
            # Build the type constraints list for the variable.
            my $num_types := 0;
            my $type_cons := PAST::Op.new();
            for $<typename> {
                $type_cons.push( $( $_ ) );
                $num_types := $num_types + 1;
            }

            # If just the one, we try to look it up and assign it.
            if $num_types == 1 {
                $past := PAST::Op.new(
                    :pasttype('copy'),
                    :lvalue(1),
                    $past,
                    $( $<typename>[0] )
                );
            }

            # Now need to apply the type constraints. How many are there?
            if $num_types == 1 {
                # Just the first one.
                $type_cons := $type_cons[0];
            }
            else {
                # Many; make an and junction of types.
                $type_cons.pasttype('call');
                $type_cons.name('all');
            }

            # Now store these type constraints.
            $past := PAST::Op.new(
                :inline(
                      "    $P0 = new 'Hash'\n"
                    ~ "    $P0['vartype'] = %1\n"
                    ~ "    setattribute %0, '%!properties', $P0\n"
                    ~ "    %r = %0\n"
                ),
                $past,
                $type_cons
            );
        }
    }

    # Routine declaration?
    else {
        $past := $( $<routine_declarator> );

        # Don't support setting return type yet.
        if $<typename> {
            $/.panic("Setting return type of a routine not yet implemented.");
        }
    }

    make $past;
}

sub declare_attribute($/) {
    # Get the
    # class or role we're in.
    our $?CLASS;
    our $?ROLE;
    our $?PACKAGE;
    our $?BLOCK;
    my $class_def;
    if $?ROLE =:= $?PACKAGE {
        $class_def := $?ROLE;
    }
    else {
        $class_def := $?CLASS;
    }
    unless defined( $class_def ) {
        $/.panic(
                "attempt to define attribute '"
            ~ $name ~ "' outside of class"
        );
    }

    # Add attribute to class (always name it with ! twigil).
    my $variable := $<scoped><variable_decl><variable>;
    my $name := ~$variable<sigil> ~ '!' ~ ~$variable<name>;
    $class_def.push(
        PAST::Op.new(
            :pasttype('callmethod'),
            :name('!keyword_has'),
            PAST::Var.new(
                :name('Perl6Object'),
                :scope('package')
            ),
            PAST::Var.new(
                :name('$def'),
                :scope('lexical')
            ),
            PAST::Val.new( :value($name) )
        )
    );

    # If we have no twigil, make $name as an alias to $!name.
    if $variable<twigil>[0] eq '' {
        $?BLOCK.symbol(
            ~$variable<sigil> ~ ~$variable<name>, :scope('attribute')
        );
    }

    # If we have a . twigil, we need to generate an accessor.
    elsif $variable<twigil>[0] eq '.' {
        my $accessor := PAST::Block.new(
            PAST::Stmts.new(
                PAST::Var.new( :name($name), :scope('attribute') )
            ),
            :name(~$variable<name>),
            :blocktype('declaration'),
            :pirflags(':method'),
            :node( $/ )
        );
        $?CLASS.unshift($accessor);
    }

    # If it's a ! twigil, we're done; otherwise, error.
    elsif $variable<twigil>[0] ne '!' {
        $/.panic(
                "invalid twigil "
            ~ $variable<twigil>[0] ~ " in attribute declaration"
        );
    }

    # Is there any "handles" trait verb?
    if $<scoped><variable_decl><trait> {
        for $<scoped><variable_decl><trait> {
            if $_<trait_verb><sym> eq 'handles' {
                # Get the methods for the handles and add them to
                # the class
                my $meths := process_handles(
                    $/,
                    $( $_<trait_verb><EXPR> ),
                    $name
                );
                for @($meths) {
                    $class_def.push($_);
                }
            }
        }
    }

    # Register the attribute in the scope.
    $?BLOCK.symbol($name, :scope('attribute'));

}

method scope_declarator($/) {
    my $past;
    our $?BLOCK;
    my $declarator := $<declarator>;

    # What sort of thing are we scoping?
    if $<scoped><variable_decl> {
        # Variable. Now go by declarator.
        if $declarator eq 'has' {
            # Has declarations are attributes and need special handling. 
            declare_attribute($/);

            # We don't want to generate any PAST at the point of the declaration.
            $past := PAST::Stmts.new();
        }
        else {
            # We need to find the actual variable PAST node; we may have something
            # more complex at this stage that applies types.
            $past := $( $<scoped> );
            my $var;
            if $past.WHAT() eq 'Var' {
                $var := $past;
            }
            else {
                # It had an initial type assignment.
                $var := $past[0][0];
            }

            # Has this already been declared?
            my $name := $var.name();
            unless $?BLOCK.symbol($name) {
                my $scope := 'lexical';
                if $declarator eq 'my' {
                    $var.isdecl(1);
                }
                elsif $declarator eq 'our' {
                    $name := $var.name();
                    $scope := 'package';
                    $var.isdecl(1);
                }
                else {
                    $/.panic(
                          "scope declarator '"
                        ~ $declarator ~ "' not implemented"
                    );
                }
                my $untyped := $var =:= $past;
                $?BLOCK.symbol($name, :scope($scope), :untyped($untyped));
            }
        }
    }

    # Routine?
    elsif $<scoped><routine_declarator> {
        $past := $( $<scoped> );

        # What declarator?
        if $declarator eq 'our' {
            # Default, nothing to do.
        }
        elsif $declarator eq 'my' {
            if $<scoped><routine_declarator><sym> eq 'method' {
                $/.panic("Private methods not yet implemented.");
            }
            else {
                $/.panic("Lexically scoped subs not yet implemented.");
            }
        }
        else {
            $/.panic("Cannot apply declarator '" ~ $declarator ~ "' to a routine.");
        }
    }

    # Something else we've not implemetned yet?
    else {
        $/.painc("Don't know how to apply a scope declarator here.");
    }

    make $past;
}


method variable($/, $key) {
    my $past;
    if $key eq 'special_variable' {
        $past := $( $<special_variable> );
    }
    elsif $key eq '$0' {
        $past := PAST::Var.new(
            :scope('keyed'),
            :node($/),
            :viviself('Undef'),
            PAST::Var.new(
                :scope('lexical'),
                :name('$/')
            ),
            PAST::Val.new(
                :value(~$<matchidx>),
                :returns('Int')
            )
        );
    }
    elsif $key eq '$<>' {
        $past := $( $<postcircumfix> );
        $past.unshift(PAST::Var.new(
            :scope('lexical'),
            :name('$/'),
            :viviself('Undef')
        ));
    }
    else {
        our $?BLOCK;
        # Handle naming.
        my @ident := $<name><ident>;
        my $name;
        PIR q<  $P0 = find_lex '@ident'  >;
        PIR q<  $P0 = clone $P0          >;
        PIR q<  store_lex '@ident', $P0  >;
        PIR q<  $P1 = pop $P0            >;
        PIR q<  store_lex '$name', $P1   >;

        my $twigil := ~$<twigil>[0];
        my $sigil := ~$<sigil>;
        my $fullname := $sigil ~ $twigil ~ ~$name;

        if $fullname eq '@_' || $fullname eq '%_' {
            unless $?BLOCK.symbol($fullname) {
                $?BLOCK.symbol( $fullname, :scope('lexical') );
                my $var;
                if $sigil eq '@' {
                    $var := PAST::Var.new( :name($fullname), :scope('parameter'), :slurpy(1) );
                }
                else {
                    $var := PAST::Var.new( :name($fullname), :scope('parameter'), :slurpy(1), :named(1) );
                }
                $?BLOCK[0].unshift($var);
            }
        }

        if $twigil eq '^' || $twigil eq ':' {
            if $?BLOCK.symbol('___HAVE_A_SIGNATURE') {
                $/.panic('A signature must not be defined on a sub that uses placeholder vars.');
            }
            $?BLOCK.symbol('___HAS_PLACEHOLDERS', :scope('lexical'));
            unless $?BLOCK.symbol($fullname) {
                $?BLOCK.symbol( $fullname, :scope('lexical') );
                my $var;
                if $twigil eq ':' {
                    $var := PAST::Var.new( :name($fullname), :scope('parameter'), :named( ~$name ) );
                }
                else {
                    $var := PAST::Var.new( :name($fullname), :scope('parameter') );
                }
                my $block := $?BLOCK[0];
                my $i := +@($block);
                my $done := 0;
                while $i >= 0 && !$done{
                    my $minusblock;
                    PIR q<  $P0 = find_lex '$i'  >;
                    PIR q<  $P1 = find_lex '$block'  >;
                    PIR q<  $I0 = $P0  >;
                    PIR q<  $I0 = $I0 - 1  >;
                    PIR q<  set $P2, $P1[$I0]  >;
                    PIR q<  store_lex '$minusblock', $P2  >;
                    # if $var<name> gt $block[$i-1]<name> ...
                    if $var<name> gt $minusblock<name> || $i == 0 {
                        # $block[$i] := $var;
                        PIR q<  $P0 = find_lex '$block'   >;
                        PIR q<  $P1 = find_lex '$i'   >;
                        PIR q<  $P2 = find_lex '$var'   >;
                        PIR q<  $I0 = $P1 >;
                        PIR q<  set $P0[$I0], $P2 >;
                        $done := 1;
                    }
                    else {
                        #$block[$i] := $block[$i-1];
                        PIR q<  $P0 = find_lex '$block'   >;
                        PIR q<  $P1 = find_lex '$i'   >;
                        PIR q<  $I0 = $P1 >;
                        PIR q<  $I1 = $I0 - 1 >;
                        PIR q<  set $P2, $P0[$I1] >;
                        PIR q<  set $P0[$I0], $P2 >;
                    }
                    $i--;
                }
            }
        }

        if $fullname eq '$_' && !$?BLOCK.symbol('___HAVE_A_SIGNATURE') {
            $?BLOCK.symbol('___MAYBE_NEED_TOPIC_FIXUP', :scope('lexical'));
        }

        # If it's $.x, it's a method call, not a variable.
        if $twigil eq '.' {
            $past := PAST::Op.new(
                :node($/),
                :pasttype('callmethod'),
                :name($name),
                PAST::Op.new(
                    :inline('%r = self')
                )
            );
        }
        else {
            # Variable. Set how it vivifies.
            my $viviself := 'Undef';
            if $<sigil> eq '@' { $viviself := 'List'; }
            if $<sigil> eq '%' { $viviself := 'Perl6Hash'; }

            # [!:^] twigil should be kept in the name.
            if $twigil eq '!' || $twigil eq ':' || $twigil eq '^' { $name := $twigil ~ ~$name; }

            # All but subs should keep their sigils.
            my $sigil := '';
            if $<sigil> ne '&' {
                $sigil := ~$<sigil>;
            }

            # If we have no twigil, but we see the name noted as an attribute in
            # an enclosing scope, add the ! twigil anyway; it's an alias.
            if $<twigil>[0] eq '' {
                our @?BLOCK;
                for @?BLOCK {
                    if defined( $_ ) {
                        my $sym_table := $_.symbol($sigil ~ $name);
                        if defined( $sym_table )
                                && $sym_table<scope> eq 'attribute' {
                            $name := '!' ~ $name;
                        }
                    }
                }
            }

            $past := PAST::Var.new(
                :name( $sigil ~ $name ),
                :viviself($viviself),
                :node($/)
            );
            if @ident || $twigil eq '*' {
                $past.namespace(@ident);
                $past.scope('package');
            }
        }
    }
    make $past;
}


method circumfix($/, $key) {
    my $past;
    if $key eq '( )' {
        $past := $( $<statementlist> );
    }
    if $key eq '[ ]' {
        $past := $( $<statementlist> );
    }
    elsif $key eq '{ }' {
        $past := $( $<pblock> );
    }
    make $past;
}


method value($/, $key) {
    make $( $/{$key} );
}


method number($/, $key) {
    make $( $/{$key} );
}


##  for a variety of reasons, this is easier in PIR than NQP for now.
##  NQP doesn't have assign yet, and Perl6Str is lighter-weight than Str.
method integer($/) {
    my $str;
    PIR q<  $P0 = find_lex '$/'   >;
    PIR q<  $S0 = $P0             >;
    PIR q<  $P1 = new 'Perl6Str'  >;
    PIR q<  assign $P1, $S0       >;
    PIR q<  store_lex '$str', $P1 >;
    make PAST::Val.new(
        :value( +$str ),
        :returns('Int'),
        :node( $/ )
    );
}


method dec_number($/) {
    make PAST::Val.new( :value( +$/ ), :returns('Num'), :node( $/ ) );
}

method radint($/, $key) {
    make $( $/{$key} );
}

method rad_number($/) {
    my $radix    := ~$<radix>;
    my $intpart  := ~$<intpart>;
    my $fracpart := ~$<fracpart>;
    my $base;
    my $exp;
    if defined( $<base>[0] ) { $base := $<base>[0].text(); }
    if defined( $<exp>[0] ) { $exp := $<exp>[0].text(); }
    if ~$<postcircumfix> {
        my $radcalc := $( $<postcircumfix> );
        $radcalc.name('radcalc');
        $radcalc.pasttype('call');
        $radcalc.unshift( PAST::Val.new( :value( $radix ), :node( $/ ) ) );
        make $radcalc;
    }
    else{
        my $return_type := 'Int';
        if $fracpart { $return_type := 'Num'; }
        make PAST::Val.new(
            :value( radcalc( $radix, $intpart, $fracpart, ~$base, ~$exp ) ),
            :returns($return_type),
            :node( $/ )
        );
    }
}


method quote($/) {
    make $( $<quote_expression> );
}

method quote_expression($/, $key) {
    my $past;
    if $key eq 'quote_regex' {
        our $?NS;
        $past := PAST::Block.new(
            $<quote_regex>,
            :compiler('PGE::Perl6Regex'),
            :namespace($?NS),
            :blocktype('declaration'),
            :node( $/ )
        );
    }
    elsif $key eq 'quote_concat' {
        if +$<quote_concat> == 1 {
            $past := $( $<quote_concat>[0] );
        }
        else {
            $past := PAST::Op.new(
                :name('list'),
                :pasttype('call'),
                :node( $/ )
            );
            for $<quote_concat> {
                $past.push( $($_) );
            }
        }
    }
    make $past;
}


method quote_concat($/) {
    my $terms := +$<quote_term>;
    my $count := 1;
    my $past := $( $<quote_term>[0] );
    while ($count != $terms) {
        $past := PAST::Op.new(
            $past,
            $( $<quote_term>[$count] ),
            :pirop('n_concat'),
            :pasttype('pirop')
        );
        $count := $count + 1;
    }
    make $past;
}


method quote_term($/, $key) {
    my $past;
    if ($key eq 'literal') {
        $past := PAST::Val.new(
            :value( ~$<quote_literal> ),
            :returns('Perl6Str'), :node($/)
        );
    }
    if ($key eq 'variable') {
        $past := $( $<variable> );
    }
    make $past;
}


method typename($/) {
    my $ns := $<name><ident>;
    my $shortname;
    PIR q<    $P0 = find_lex '$ns'         >;
    PIR q<    $P0 = clone $P0              >;
    PIR q<    $P1 = pop $P0                >;
    PIR q<    store_lex '$ns', $P0         >;
    PIR q<    store_lex '$shortname', $P1  >;
    make PAST::Var.new(
        :name($shortname),
        :namespace($ns),
        :scope('package'),
        :node($/)
    );
}


method subcall($/) {
    # Build call node.
    my $past := PAST::Op.new(
        :name( ~$<ident> ),
        :pasttype('call'),
        :node($/)
    );

    # Process arguments.
    my $args := $( $<semilist> );
    process_arguments($past, $args);

    make $past;
}


method semilist($/) {
    my $past := PAST::Op.new( :node($/) );
    if $<EXPR> {
        my $expr := $($<EXPR>[0]);
        if $expr.name() eq 'infix:,' {
            for @($expr) {
                $past.push( $_ );
            }
        }
        else {
            $past.push( $expr );
        }
    }
    make $past;
}


method listop($/, $key) {
    my $past;
    if $key eq 'arglist' {
        $past := $( $<arglist> );
    }
    if $key eq 'noarg' {
        $past := PAST::Op.new( );
    }
    $past.name( ~$<sym> );
    $past.pasttype('call');
    $past.node($/);
    make $past;
}


method arglist($/) {
    my $past := PAST::Op.new( :node($/) );
    my $expr := $($<EXPR>);
    if $expr.name() eq 'infix:,' {
        for @($expr) {
            $past.push( $_ );
        }
    }
    else {
        $past.push( $expr );
    }
    make $past;
}


method EXPR($/, $key) {
    if $key eq 'end' {
        make $($<expr>);
    }
    elsif ~$<type> eq 'infix:.=' {
        my $var := $( $/[0] );
        my $res := $var;
        my $call := $( $/[1] );

        # Check that we have a sub call.
        if $call.WHAT() ne 'Op' || $call.pasttype() ne 'call' {
            $/.panic('.= must have a call on the right hand side');
        }

        # If it was a scoped declarator with types, need to just get the
        # PAST::Var node for the result.
        if $/[0]<noun><scope_declarator><scoped><variable_decl> {
            # Note we create a new Var node, since we don't want both of them
            # to be declarations.
            my $info := $( $/[0]<noun><scope_declarator><scoped><variable_decl><variable> );
            $res := PAST::Var.new(
                :name($info.name()),
                :scope($info.scope())
            );
        }

        # Create call and assign result nodes.
        my $meth_call := PAST::Op.new(
            :pasttype('callmethod'),
            :name($call.name()),
            :node($/),
            $var
        );
        my $past := PAST::Op.new(
            :inline("    %r = '!TYPECHECKEDASSIGN'(%1, %0)\n"),
            :node($/),
            $meth_call,
            $res
        );

        # Copy arguments.
        for @($call) {
            $meth_call.push($_);
        }

        make $past;
    }
    else {
        my $past := PAST::Op.new(
            :name($<type>),
            :pasttype($<top><pasttype>),
            :pirop($<top><pirop>),
            :lvalue($<top><lvalue>),
            :node($/)
        );
        for @($/) {
            unless +$_.from() == +$_.to() { $past.push( $($_) ) };
        }

        # If it's an assignment or binding, we may need to emit a type-check.
        if $past.name() eq 'infix:=' {
            # We can skip it if we statically know the variable had no type
            # associated with it, though.
            our $?BLOCK;
            my $sym_info := $?BLOCK.symbol($past[0].name());
            unless $sym_info<untyped> {
                $past := PAST::Op.new(
                    :lvalue(1),
                    :node($/),
                    :inline("    %r = '!TYPECHECKEDASSIGN'(%0, %1)\n"),
                    $past[0],
                    $past[1]
                );
            }
        }

        make $past;
    }
}


method regex_declarator($/, $key) {
    make $( $/{$key} );
}


method regex_declarator_regex($/) {
    my $past := $( $<quote_expression> );
    $past.name( ~$<ident>[0] );
    make $past;
}


method regex_declarator_token($/) {
    my $past := $( $<quote_expression> );
    $past.compiler_args( :ratchet(1) );
    $past.name( ~$<ident>[0] );
    make $past;
}


method regex_declarator_rule($/) {
    my $past := $( $<quote_expression> );
    $past.compiler_args( :s(1), :ratchet(1) );
    $past.name( ~$<ident>[0] );
    make $past;
}


method type_declarator($/) {
    # We need a block containing the constraint condition.
    my $past := $( $<EXPR> );
    if $past.WHAT() ne 'Block' {
        # Make block with the expression as its contents.
        $past := PAST::Block.new(
            PAST::Stmts.new(),
            PAST::Stmts.new( $past )
        );
    }

    # Make sure it has a parameter and keep hold of it if found.
    my $param;
    my $dollar_underscore;
    for @($past[0]) {
        if $_.WHAT() eq 'Var' {
            if $_.scope() eq 'parameter' {
                $param := $_;
            }
            elsif $_.name() eq '$_' {
                $dollar_underscore := $_;
            }
        }
    }
    unless $param {
        if $dollar_underscore {
            $dollar_underscore.scope('parameter');
            $param := $dollar_underscore;
        }
        else {
            $param := PAST::Var.new(
                :name('$_'),
                :scope('parameter')
            );
            $past[0].push($param);
        }
    }

    # Do we have an existing constraint to check?
    if $<typename> {
        my $new_cond := $past[1];
        my $prev_cond := $( $<typename>[0] );
        $past[1] := PAST::Op.new(
            :pasttype('if'),
            PAST::Op.new(
                :pasttype('callmethod'),
                :name('ACCEPTS'),
                $prev_cond,
                PAST::Var.new(
                    :name($param.name())
                )
            ),
            $new_cond
        )
    }

    # Set block details.
    $past.node($/);

    # Now we need to create the block wrapper class.
    $past := PAST::Op.new(
        :pasttype('callmethod'),
        :name('!create'),
        PAST::Var.new(
            :name('Subset'),
            :scope('package')
        ),
        PAST::Val.new( :value(~$<name>) ),
        $past
    );

    make $past;
}


method fatarrow($/) {
    my $key := PAST::Val.new( :value(~$<key>),
                               :named( PAST::Val.new( :value('key') ) ) );
    my $val := $( $<val> );
    $val.named( PAST::Val.new( :value('value') ) );
    my $past := PAST::Op.new(
        :node($/),
        :pasttype('callmethod'),
        :name('new'),
        :returns('Pair'),
        PAST::Var.new(
            :name('Pair'),
            :scope('package')
        ),
        $key,
        $val
    );
    make $past;
}


method colonpair($/, $key) {
    my $pair_key;
    my $pair_val;

    if $key eq 'false' {
        $pair_key := PAST::Val.new( :value(~$<ident>) );
        $pair_val := PAST::Val.new( :value(0), :returns('Int') );
    }
    elsif $key eq 'value' {
        $pair_key := PAST::Val.new( :value(~$<ident>) );
        if $<postcircumfix> {
            # What type of postcircumfix?
            my $type := substr($<val>, 0, 1);
            if $type eq '(' {
                my $val := $( $<postcircumfix><semilist> );
                $pair_val := $val[0];
            }
            elsif $type eq '<' {
                $pair_val := $( $<postcircumfix><quote_expression> );
            }
            else {
                $/.panic($type ~ ' postcircumfix colonpairs not yet implemented');
            }
        }
        else {
            $pair_val := PAST::Val.new( :value(1), :returns('Int') );
        }
    }
    elsif $key eq 'varname' {
        if $<desigilname><name> {
            $pair_key := PAST::Val.new( :value( ~$<desigilname> ) );
            $pair_val := PAST::Var.new(
                :name( ~$<sigil> ~ ~$<twigil> ~ ~$<desigilname> )
            );
        }
        else {
            $/.panic('complex varname colonpair case not yet implemented');
        }
    }
    else {
        $/.panic($key ~ " pairs not yet implemented.");
    }

    $pair_key.named( PAST::Val.new( :value('key') ) );
    $pair_val.named( PAST::Val.new( :value('value') ) );
    my $past := PAST::Op.new(
        :node($/),
        :pasttype('callmethod'),
        :name('new'),
        :returns('Pair'),
        PAST::Var.new(
            :name('Pair'),
            :scope('package')
        ),
        $pair_key,
        $pair_val
    );
    make $past;
}


method capterm($/) {
    # We will create the capture object, passing the things supplied.
    my $past := PAST::Op.new(
        :pasttype('callmethod'),
        :name('!create'),
        PAST::Var.new(
            :name('Capture'),
            :scope('package')
        )
    );

    # First parameter is invocant. XXX null for now, we're not parsing it.
    $past.push( PAST::Op.new( :inline('%r = null') ) );

    # Process arguments.
    process_arguments($past, $( $<capture> ));

    make $past;
}


method capture($/) {
    my $expr := $( $<EXPR> );
    my $past := PAST::Op.new();
    if $expr.name() eq 'infix:,' {
        for @($expr) {
            $past.push( $_ );
        }
    }
    else {
        $past.push( $expr );
    }
    make $past;
}


# Used by all calling code to process arguments into the correct form.
sub process_arguments($call_past, $args) {
    for @($args) {
        if $_.returns() eq 'Pair' {
            $_[2].named($_[1]);
            $call_past.push($_[2]);
        }
        else {
            $call_past.push($_);
        }
    }
}


# Processes a handles expression to produce the appropriate method(s).
sub process_handles($/, $expr, $attr_name) {
    my $past := PAST::Stmts.new();

    # What type of expression do we have?
    if $expr.WHAT() eq 'Val' && $expr.returns() eq 'Perl6Str' {
        # Just a single string mapping.
        my $name := ~$expr.value();
        $past.push(make_handles_method($/, $name, $name, $attr_name));
    }
    elsif $expr.WHAT() eq 'Op' && $expr.returns() eq 'Pair' {
        # Single pair.
        $past.push(make_handles_method_from_pair($/, $expr, $attr_name));
    }
    elsif $expr.WHAT() eq 'Op' && $expr.pasttype() eq 'call' &&
          $expr.name() eq 'list' {
        # List of something, but what is it?
        for @($expr) {
            if $_.WHAT() eq 'Val' && $_.returns() eq 'Perl6Str' {
                # String value.
                my $name := ~$_.value();
                $past.push(make_handles_method($/, $name, $name, $attr_name));
            }
            elsif $_.WHAT() eq 'Op' && $_.returns() eq 'Pair' {
                # Pair.
                $past.push(make_handles_method_from_pair($/, $_, $attr_name));
            }
            else {
                $/.panic(
                    'Only a list of constants or pairs can be used in handles'
                );
            }
        }
    }
    elsif $expr.WHAT() eq 'Stmts' && $expr[0].name() eq 'infix:,' {
        # Also a list, but constructed differently.
        for @($expr[0]) {
            if $_.WHAT() eq 'Val' && $_.returns() eq 'Perl6Str' {
                # String value.
                my $name := ~$_.value();
                $past.push(make_handles_method($/, $name, $name, $attr_name));
            }
            elsif $_.WHAT() eq 'Op' && $_.returns() eq 'Pair' {
                # Pair.
                $past.push(make_handles_method_from_pair($/, $_, $attr_name));
            }
            else {
                $/.panic(
                    'Only a list of constants or pairs can be used in handles'
                );
            }
        }
    }
    else {
        $/.panic('Illegal or unimplemented use of handles');
    }

    $past
}


# Produces a handles method.
sub make_handles_method($/, $from_name, $to_name, $attr_name) {
    PAST::Block.new(
        :name($from_name),
        :pirflags(':method'),
        :blocktype('declaration'),
        :node($/),
        PAST::Var.new(
            :name('@a'),
            :scope('parameter'),
            :slurpy(1)
        ),
        PAST::Var.new(
            :name('%h'),
            :scope('parameter'),
            :named(1),
            :slurpy(1)
        ),
        PAST::Op.new(
            :name($to_name),
            :pasttype('callmethod'),
            PAST::Var.new(
                :name($attr_name),
                :scope('attribute')
            ),
            PAST::Var.new(
                :name('@a'),
                :scope('lexical'),
                :flat(1)
            ),
            PAST::Var.new(
                :name('%h'),
                :scope('lexical'),
                :flat(1),
                :named(1)
            )
        )
    )
}


# Makes a handles method from a pair.
sub make_handles_method_from_pair($/, $pair, $attr_name) {
    my $meth;

    # Single pair mapping. Check we have string name and value.
    my $key := $pair[1];
    my $value := $pair[2];
    if $key.WHAT() eq 'Val' && $value.WHAT() eq 'Val' {
        my $from_name := ~$key.value();
        my $to_name := ~$value.value();
        $meth := make_handles_method($/, $from_name, $to_name, $attr_name);
    }
    else {
        $/.panic('Only constants may be used in a handles pair argument.');
    }

    $meth
}


# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:

package tcl

// ReachingAt returns the local-variable bindings that may reach the use at byte
// offset useOff in src, as Definition values (Kind DefLocal/DefGlobalLink, with
// NameStart/NameEnd on the binding's name token and Origin for links). ok is
// false when useOff is not on a proc-local variable use or no in-proc binding
// reaches it. Intraprocedural and may-reach (over-approximate, never drops a real
// reaching def). Later tasks add control-flow precision; this task handles a
// straight-line proc body.
func ReachingAt(src string, useOff int) (defs []Definition, ok bool) {
	inner, innerBase, argsWord, argsBase, found := enclosingProc(Parse(src), 0, "::", FrameNamespace, 0, useOff)
	if !found {
		return nil, false
	}
	a := &analyzer{useOff: useOff}
	entry := reachSet{}
	// Seed entry set with proc params.
	var paramDefs []Definition
	emitProcParams(argsWord, argsBase, "::", innerBase, &paramDefs)
	for _, d := range paramDefs {
		entry[d.Name] = []Definition{d}
	}
	a.seq(Parse(inner), innerBase, entry)
	if !a.found {
		return nil, false
	}
	return a.answer, true
}

// enclosingProc returns the interior text and absolute base of the innermost proc
// body containing useOff, plus the proc's args Word and the base for interpreting
// it. A proc-introducing body is FrameProc with Scope==Base (childBodies sets a
// proc body's Scope to its own interior offset; control-flow bodies keep the
// enclosing scope).
func enclosingProc(cmds []Command, base int, ns string, frame FrameKind, scope, useOff int) (inner string, innerBase int, argsWord Word, argsBase int, found bool) {
	for _, c := range cmds {
		for _, b := range childBodies(c, base, ns, frame, scope) {
			if useOff < b.Base || useOff >= b.Base+len(b.Inner) {
				continue
			}
			// Try to find a deeper (more nested) proc first.
			if in2, base2, aw2, ab2, ok2 := enclosingProc(Parse(b.Inner), b.Base, b.NS, b.Frame, b.Scope, useOff); ok2 {
				return in2, base2, aw2, ab2, true
			}
			// This body is the innermost one containing useOff. Check if it is a
			// proc frame (Scope==Base means childBodies set it as a proc body's
			// own interior, not a control-flow body sharing the enclosing scope).
			if b.Frame == FrameProc && b.Scope == b.Base {
				// Recover the args word from the proc command.
				aw, ab := procArgsWord(c, base)
				return b.Inner, b.Base, aw, ab, true
			}
		}
	}
	return "", 0, Word{}, 0, false
}

// procArgsWord returns the args Word and base for the proc command c (or a
// decorated proc). Returns a zero Word when the command is not a proc.
func procArgsWord(c Command, base int) (Word, int) {
	w := c.Words
	if isCmd(w, "proc") && len(w) >= 4 {
		return w[2], base
	}
	if _, args, _, ok := decoratedProcDef(w); ok {
		return args, base
	}
	return Word{}, base
}

// reachSet maps a local variable name to the bindings that may currently reach
// this program point.
type reachSet map[string][]Definition

func (s reachSet) clone() reachSet {
	out := make(reachSet, len(s))
	for k, v := range s {
		cp := make([]Definition, len(v))
		copy(cp, v)
		out[k] = cp
	}
	return out
}

type analyzer struct {
	useOff int
	answer []Definition
	found  bool
}

// seq threads the reaching set left-to-right through a command sequence and
// returns the set at its end. (Control-flow live/stop handling is added in a
// later task; here every command continues.)
func (a *analyzer) seq(cmds []Command, base int, in reachSet) reachSet {
	cur := in
	for _, c := range cmds {
		cur = a.command(c, base, cur)
	}
	return cur
}

// command applies one command: record any variable use at useOff against the
// incoming set, then apply this command's bindings (kill prior, gen new).
func (a *analyzer) command(c Command, base int, in reachSet) reachSet {
	a.recordUses(c, base, in)
	binds := localBindings(c, base)
	if len(binds) == 0 {
		return in
	}
	out := in.clone()
	for _, d := range binds {
		out[d.Name] = []Definition{d} // straight-line: reassign kills+gens
	}
	return out
}

// recordUses snapshots the reaching set for the variable used at useOff (a
// $-substituted RefVariable in this command's own words).
func (a *analyzer) recordUses(c Command, base int, in reachSet) {
	if a.found {
		return
	}
	for _, r := range CommandRefs(c) {
		if r.Kind != RefVariable {
			continue
		}
		s, e := r.Start+base, r.End+base
		if a.useOff >= s && a.useOff < e {
			a.answer = append([]Definition(nil), in[r.Name]...)
			a.found = true
			return
		}
	}
}

// localBindings returns the variable bindings introduced by a single command c,
// applying the same rules as emitDefs but always as if inside a proc frame
// (since localBindings is only called on commands inside a proc body).
// base is the absolute offset of the parse context that produced c's offsets.
func localBindings(c Command, base int) []Definition {
	var out []Definition
	w := c.Words
	if len(w) == 0 {
		return nil
	}

	// set x VAL  (proc-local scalar or array base)
	if isCmd(w, "set") && len(w) >= 2 {
		if name, s, e, ok := arrayBaseName(w[1]); ok {
			out = append(out, Definition{
				Kind: DefLocal, Name: name,
				NameStart: base + s, NameEnd: base + e,
			})
		}
	}

	// incr / append / lappend x ...
	if len(w) >= 2 {
		switch {
		case isCmd(w, "incr"), isCmd(w, "append"), isCmd(w, "lappend"):
			if name, s, e, ok := arrayBaseName(w[1]); ok {
				out = append(out, Definition{
					Kind: DefLocal, Name: name,
					NameStart: base + s, NameEnd: base + e,
				})
			}
		}
	}

	// variable NAME ?val? (proc frame: also a local link to the ns var)
	if isCmd(w, "variable") && len(w) >= 2 && isPlainName(w[1]) {
		out = append(out, Definition{
			Kind: DefLocal, Name: w[1].Text,
			NameStart: base + w[1].Start, NameEnd: base + w[1].End,
		})
	}

	// global NAME ... (DefGlobalLink per name)
	if isCmd(w, "global") {
		for _, gw := range w[1:] {
			if isPlainName(gw) {
				out = append(out, Definition{
					Kind: DefGlobalLink, Name: gw.Text,
					NameStart: base + gw.Start, NameEnd: base + gw.End,
					Origin: globalOrigin(gw.Text),
				})
			}
		}
	}

	// upvar ?level? otherVar alias ?otherVar alias ...?
	if isCmd(w, "upvar") && len(w) >= 3 {
		args := w[1:]
		level := ""
		if len(args) > 0 && isUpvarLevel(args[0]) {
			level = args[0].Text
			args = args[1:]
		}
		for i := 1; i < len(args); i += 2 {
			alias := args[i]
			if isPlainName(alias) {
				out = append(out, Definition{
					Kind: DefLocal, Name: alias.Text,
					NameStart: base + alias.Start, NameEnd: base + alias.End,
					Origin: upvarOrigin(level, args[i-1]),
				})
			}
		}
	}

	// foreach / lmap / lassign / dict for|map — loop var lists
	emitLoopVarDefs(w, base, "::", 0, &out)

	return out
}

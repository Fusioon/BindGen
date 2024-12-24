using System;
using System.IO;
using System.Collections;

namespace BindGen;

class Preprocessor
{
	public class DefineDef
	{
		public append String name;

		public append List<String> args;

		public append String value;
	}

	public append List<String> includePaths;

	append BumpAllocator alloc;

	public append Dictionary<String, DefineDef> defines;

	public Event<delegate bool(StringView includeFilePath)> onFileInclude ~ _.Dispose();

	class IfBlockDef
	{
		IfBlockDef _parent;
		public IfBlockDef Parent
		{
			get => _parent;
			set
			{
				Runtime.Assert(_parent == null);
				_parent = value;
			}
		}	 

		append String _condition;
		public StringView Condition
		{
			get => _condition;
			set => _condition.Set(value);
		}

		bool? _result;
		public bool Result => _result.Value;

		String _file;
		int _line;

		public void SetPositionData(String file, int line)
		{
			_file = _file;
			_line = line;
		}

		public void SetResultConstant(bool value)
		{
			_result = value;
		}

		public Result<bool> ComputeExpression(Preprocessor preproc)
		{
			if (_result.TryGetValue(let val))
				return .Ok(val);

			return .Err;
		}
	}

	class Source
	{
		public bool reachedEnd = false;
		public char8 currentChar = 0;

		append String _file;
		public StringView FilePath => _file;

		int _line;
		public int Line => _line;
		int _pos;
		public int Position => _pos;

		StreamReader _reader;

		public append List<char8> skippedChars = .(8);

		public IfBlockDef _currentBlock;

		public (String file, int line, int pos) GetPosition() => (_file, _line, _pos); 

		[AllowAppend]
		public this(Stream fs, StringView filePath)
		{
			StreamReader reader = append .(fs);

			_reader = reader;
			_file.Set(filePath);
			_line = 1;
			_pos = 0;
		}

		public Result<char8> Advance()
		{
			if (_reader.EndOfStream)
			{
				reachedEnd = true;
				return .Err;
			}

			_pos++;
			switch (_reader.Read())
			{
			case .Ok(let c):
				{
					if (c == '\n')
						_line++;

					currentChar = c;
					return .Ok(c);
				}
			case .Err:
			}

			reachedEnd = true;
			return .Err;
		}
	}

	Source _source;

	append List<String> _includeOnce = .(64);

	[Inline]
	char8 CurrentChar => _source.currentChar;

	IfBlockDef CurrentBlock
	{
		[Inline]
		get => _source._currentBlock;
		[Inline]
		set
		{
			_source._currentBlock = value;
		}
	}

	bool IsBlockIgnored => (CurrentBlock != null) && (CurrentBlock.Result == false);

	[Inline]
	void Advance()
	{
		if (_source.skippedChars.Count > 0)
		{
			_source.currentChar = _source.skippedChars.PopBack();
			return;
		}

		if (_source.Advance() case .Ok(let c) && c == '/')
		{
			if (_source.Advance() case .Ok(let next))
			{
				switch (next)
				{
				case '/': SkipUntilNewline();
				case '*': SkipBlockComment();

				default:
					_source.skippedChars.Add(next);
					_source.currentChar = c;
				}
			}
		}
	}

	[Inline]
	bool HasData => !_source.reachedEnd;

	void PushBlock(IfBlockDef block)
	{
		block.Parent = CurrentBlock;
		CurrentBlock = block;
	}

	void PopBlock()
	{
		CurrentBlock = CurrentBlock.Parent;
	}

	void ParseIdentifier(String identifier)
	{
		bool IsValidIdentifier(char8 c) => c.IsLetterOrDigit || c == '_';
			
		while (HasData)
		{
			if (!IsValidIdentifier(CurrentChar))
				break;

			identifier.Append(CurrentChar);
			Advance();
		}
	}

	void SkipWhitespace()
	{
		while (HasData)
		{
			switch (CurrentChar)
			{
			case ' ', '\t':

			default:
				return;
			}

			Advance();
		}
	}

	void SkipUntilNewline()
	{
		while (HasData)
		{
			if (CurrentChar == '\n')
				return;

			Advance();
		}
	}

	void SkipBlockComment()
	{
		while (HasData)
		{
			if (CurrentChar == '*')
			{
				Advance();
				if (CurrentChar == '/')
					return;

				continue;
			}

			Advance();
		}

		NOP!();
	}

	void ParseString(String buffer)
	{

		while (HasData)
		{
			if (CurrentChar == '\\')
			{
				Advance();
				switch (CurrentChar)
				{
				case 'n': buffer.Append('\n');
				case 'r': buffer.Append('\r');

				case 'a': buffer.Append('\a');
				case 't': buffer.Append('\t');
				case 'v': buffer.Append('\v');
				case 'f': buffer.Append('\f');

				case '0': buffer.Append('\0');
				case '"': buffer.Append('"');
				case '\\': buffer.Append('\\');

				case 'x':
					{
						// Hexadecimal
						Runtime.NotImplemented();
					}

				default:
					{
						if (CurrentChar.IsDigit)
						{
							// @TODO
							Runtime.NotImplemented();
						}

						continue;
					}
				}
			}
			else
			{
				buffer.Append(CurrentChar);
			}

			Advance();
		}
	}

	void HandlePragma(StringView directive)
	{
		switch (directive)
		{
		case "alloc_text":
		case "auto_inline":
		case "bss_seg":
		case "check_stack":
		case "code_seg":
		case "comment":
		case "component":
		case "conform":
		case "const_seg":
		case "data_seg":
		case "deprecated":
		case "detect_mismatch":
		case "endregion":
		case "fenv_access":
		case "float_control":
		case "fp_contract":
		case "function":
		case "hdrstop":
		case "include_alias":
		case "init_seg":
		case "inline_depth":
		case "inline_recursion":
		case "loop":
		case "make_public":
		case "managed":
		case "message":
		case "omp":
		case "optimize":
		case "pack":
		case "pointers_to_members":
		case "region":
		case "runtime_checks":
		case "section":
		case "setlocale":
		case "strict_gs_check":
		case "system_header":
		case "unmanaged":
		case "vtordisp":
		case "warning":


		case "once":
			{
				_includeOnce.Add(new:alloc .(_source.FilePath));
			}

		case "push_macro", "pop_macro":
			{
				SkipWhitespace();
				if (CurrentChar == '(')
				{
					Advance();
					if (CurrentChar == '"')
					{
						String macro = scope .();
						ParseString(macro);
						Runtime.Assert(macro.Length > 0);

						Runtime.NotImplemented();
					}
				}
			}

		}
	}

	// Parses #define and #if even when ending with escaped newline
	void ParseExpression(String buffer)
	{
		while (HasData)
		{
			if (CurrentChar == '\\')
			{
				Advance();
				if (CurrentChar == '\r')
					Advance();

				if (CurrentChar == '\n')
				{
					buffer.Append(CurrentChar);
					Advance();
					continue;
				}
			}

			buffer.Append(CurrentChar);
			Advance();
		}
	}

	Result<void> HandleDirective(StringView control)
	{
		let startPosition = _source.GetPosition();

		CONTROL_SWITCH:
		switch (control)
		{
		case "include":
			{
				SkipWhitespace();
				switch (CurrentChar)
				{
				case '<', '"':
					{
						let endChar = (_ == '<') ? '>' : '"';

						String filePath = scope .();

						while (HasData)
						{
							if (CurrentChar == endChar)
							{
								Advance();
								break;
							}

							filePath.Append(CurrentChar);
							Advance();
						}

						if (IsBlockIgnored)
							break CONTROL_SWITCH;

						bool shouldInclude = true;
						if (onFileInclude.HasListeners)
							shouldInclude = onFileInclude(filePath);

						if (!shouldInclude)
							break CONTROL_SWITCH;
					}
				default:
					Runtime.FatalError();
				}
			}
		case "if", "elif":
			{
				SkipWhitespace();
				String expression = scope .();
				ParseExpression(expression);

				

			}
		case "ifdef", "ifndef":
			{
				SkipWhitespace();
				String identifier = scope .();
				ParseIdentifier(identifier);

				let blockResult = IsDefined(identifier) ^ (_ == "ifndef");
				SkipUntilNewline();

				let block = new:alloc IfBlockDef();
				block.SetPositionData(startPosition.file, startPosition.line);
				block.SetResultConstant(!IsBlockIgnored || blockResult);
				PushBlock(block);
			}
		case "else":
			{
				SkipUntilNewline();
				Runtime.Assert(CurrentBlock != null);

				let blockResult = CurrentBlock.Result;
				PopBlock();

				let block = new:alloc IfBlockDef();
				block.SetPositionData(startPosition.file, startPosition.line);
				block.SetResultConstant(!IsBlockIgnored || blockResult);
				PushBlock(block);

			}
		case "endif":
			{
				SkipUntilNewline();
				PopBlock();
			}

		case "define":
			{
				SkipWhitespace();
				String identifier = scope .();
				ParseIdentifier(identifier);

				Runtime.Assert(identifier.Length > 0);

				DefineDef def = new:alloc .();
				def.name.Set(identifier);

				if (defines.TryAdd(def.name, let keyPtr, let valPtr))
				{
					*keyPtr = def.name;
					*valPtr = def;
				}
				else
				{
					// @TODO
					Runtime.FatalError();
				}

				defines.Add(def.name, def);

				if (CurrentChar == '(')
				{
					Advance();

					identifier.Clear();
					while (HasData)
					{
						if (CurrentChar == ')')
						{
							Runtime.Assert(identifier.Length > 0);
							def.args.Add(new .(identifier));
							identifier.Clear();
							Advance();
							break;
						}

						if (CurrentChar == ',')
						{
							Runtime.Assert(identifier.Length > 0);
							def.args.Add(new .(identifier));
							identifier.Clear();
							Advance();
							continue;
						}

						if (CurrentChar.IsWhiteSpace)
						{
							Advance();
							continue;
						}

						identifier.Append(CurrentChar);
						Advance();
					}
				}

				SkipWhitespace();
				ParseExpression(def.value);
			}

		case "undefine":
			{
				SkipWhitespace();
				String identifier = scope .();
				ParseIdentifier(identifier);
				SkipUntilNewline();

				switch (defines.GetAndRemove(identifier))
				{
				case .Ok((let key, let val)):
					{
						delete:alloc val;
					}

				case .Err:
					// ...
				}
			}

		case "import":
		case "pragma":
			{
				SkipWhitespace();
				String directive = scope .();
				ParseIdentifier(directive);
				Runtime.Assert(directive.Length > 0);
				HandlePragma(directive);
			}
		case "line":
			{
				SkipWhitespace();
				String buffer = scope .();
				while (HasData)
				{
					if (!CurrentChar.IsDigit)
						break;

					buffer.Append(CurrentChar);
					Advance();
				}

				if (!IsBlockIgnored && buffer.IsEmpty)
					Runtime.FatalError();


				uint32 lineNumber = 0;
				if (!IsBlockIgnored)
					lineNumber = uint32.Parse(buffer);

				SkipWhitespace();
				if (CurrentChar == '"')
				{
					buffer.Clear();
					Advance();
					ParseString(buffer..Clear());
				}

				#unwarn
				StringView fileName = buffer;

				//SetLocation(lineNumber, fileName);

				SkipUntilNewline();
			}
		case "using":


		default:
			return .Err;
		}


		return .Ok;
	}

	public void ParseStream(StringView name, Stream stream)
	{
		_source = new:alloc .(stream, name);

		String buffer = scope .();

		while (HasData)
		{
			if (CurrentChar == '#')
			{
				Advance();
				ParseIdentifier(buffer..Clear());
				HandleDirective(buffer);
			}


			Advance();
		}

	}

	bool IsDefined(StringView name)
	{
		return defines.ContainsKeyAlt(name);
	}
}
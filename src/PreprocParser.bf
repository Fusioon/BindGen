using System;
using System.Collections;

namespace BindGen;

class PreprocParser
{
	append BumpAllocator alloc;

	public class DefineDef
	{
		public append String name;

		public append List<String> args;

		public append String value;
	}

	public append Dictionary<String, DefineDef> defines;

	void SkipWhitespace(StringView input, ref int i)
	{
		while (i < input.Length)
		{
			switch (input[i])
			{
			case '\t', ' ': i++;
			default: return;
			}
		}
	}

	Result<StringView> ParseIdentifier(StringView input, ref int i)
	{
		bool IsValidIdentifierChar(char8 c) => c.IsLetterOrDigit || c == '_';

		let start = i;

		while (i < input.Length)
		{
			if (!IsValidIdentifierChar(input[i]))
				break;

			i++;
		}

		if (start == i)
			return .Err;


		return input.Substring(start, i - start);
	}

	char8 CurrentChar(StringView input, int i)
	{
		if (i < input.Length)
			return input[i];

		return 0;
	}

	bool ExpectChar(StringView input, ref int i, char8 c)
	{
		if (CurrentChar(input, i) != c)
			return false;

		i++;
		return true;
	}

	public void HandleDefine(StringView line)
	{
		var line;
		Runtime.Assert(line.StartsWith("#define"));
		line = line.Substring("#define".Length);

		int i = 0;
		SkipWhitespace(line, ref i);
		StringView identifier = ParseIdentifier(line, ref i);

		DefineDef def = new:alloc .();
		def.name.Set(identifier);

		if (identifier == "SDL_WINDOW_FULLSCREEN")
			NOP!();

		bool addSuccess = defines.TryAdd(def.name, let keyPtr, let valPtr);
		if (addSuccess)
		{
			*keyPtr = def.name;
			*valPtr = def;
		}

		if (ExpectChar(line, ref i, '('))
		{
			while (i < line.Length)
			{
				SkipWhitespace(line, ref i);
				let c = line[i];
				if (c == ',')
				{
					i++;
					continue;
				}
				if (c == ')')
				{
					i++;
					break;
				}
				if (c == '.')
				{
					Runtime.Assert(ExpectChar(line, ref i, '.'));
					Runtime.Assert(ExpectChar(line, ref i, '.'));
					Runtime.Assert(ExpectChar(line, ref i, '.'));
					SkipWhitespace(line, ref i);
					Runtime.Assert(ExpectChar(line, ref i, ')'));
					def.args.Add("...");
					break;
				}
				StringView name = ParseIdentifier(line, ref i);
				def.args.Add(new:alloc .(name));
			}
		}

		SkipWhitespace(line, ref i);
		StringView value = line.Substring(i);
		def.value.Set(value);

		if (!addSuccess)
		{
			Runtime.Assert(def.args.Count == (*valPtr).args.Count);
			Runtime.Assert(def.value == (*valPtr).value);
		}
		
	}
}
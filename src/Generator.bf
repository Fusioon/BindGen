using System;
using System.IO;
using System.Collections;
using System.Interop;

namespace BindGen;

class Generator
{
	enum EDefineType
	{
		Unknown,
		Empty,
		Int,
		UInt,
		Float,
		Double,
		String
	}

	/// Return true when type should be replaced with underlying type
	public delegate bool OnPrimitiveTypeResolveDelegate(Parser.TypeRef type, Parser.TypeAliasDef alias);
	/// Return true when define should be generated
	public delegate bool DefinesFilterDelegate(PreprocParser.DefineDef def);

	const String INDENT_STR = "\t";
	append String _indent;

	String[?] KEYWORDS = .("internal", "function", "delegate", "where", "operator", "class", "struct", "extern", "for", "while", "do", "repeat", "abstract", "base", "virtual", "override", "extension", "namespace", "using", "out", "in", "ref");

	Parser _parser;

	append HashSet<String> _createdTypes;

	public OnPrimitiveTypeResolveDelegate onPrimitiveTypeResolve ~ delete _;
	public DefinesFilterDelegate definesFilter ~ delete _;

	void PushIndent()
	{
		_indent.Append(INDENT_STR);
	}

	void PopIndent()
	{
		_indent.RemoveFromEnd(INDENT_STR.Length);
	}

	void WriteIndent(StreamWriter writer)
	{
		writer.Write(_indent);
	}

	void WriteAttrs(Span<String> attrs, StreamWriter writer)
	{
		const String ATTR_SUFFIX = nameof(Attribute);

		if (attrs.Length > 0)
		{
			WriteIndent(writer);

			writer.Write("[");
			for (let a in attrs)
			{
				if (@a.Index != 0)
					writer.Write(", ");

				StringView attrView = a;

				if (attrView.EndsWith(ATTR_SUFFIX))
					attrView.RemoveFromEnd(ATTR_SUFFIX.Length);

				writer.Write(attrView);
			}
			writer.WriteLine("]");
		}
	}

	void WriteIdentifier(StringView name, StreamWriter writer)
	{
		for (let kw in KEYWORDS)
		{
			if (kw == name)
			{
				writer.Write("@");
				break;
			}
		}
		writer.Write(name);
	}

	Parser.ETypeAliasFlags ResolveBeefType(Parser.TypeRef type)
	{
		let c_type = type.raw;

		Parser.ETypeAliasFlags flags = .None;

		int32 i = 0;

		int32 idStart = -1;
		

		Result<StringView> GetIdentifier(int32 end)
		{
			if (idStart == -1 && end != idStart)
				return .Err;

			defer { idStart = -1; }
			return c_type[idStart..<end];
		}

		bool signed = false;
		bool unsigned = false;

		bool isLong = false;
		bool isVolatile = false;

		bool isFunction = false;
		
		while (i < c_type.Length && !isFunction)
		{
			let c = c_type[i];

			bool IsIdentifierChar(char8 c) => c.IsLetterOrDigit || c == '_';

			int32 GetSizedArrayLength()
			{
				i++;

				let start = i;
				var end = start;
				while (i < c_type.Length)
				{
					if (c_type[i] == ']')
					{
						end = i;
						break;
					}
					i++;
				}

				Runtime.Assert(end != start);
				let lengthString = c_type[start..<end];
				return int32.Parse(lengthString);
			}

			if (c == '*')
			{
				Runtime.Assert(type.typeString.Length > 0 || isLong);
				type.ptrDepth++;
			}
			else if (c == '&')
			{
				Runtime.Assert(type.typeString.Length > 0 || isLong);
				Runtime.Assert(!type.isRef);
				type.isRef = true;
			}
			else if (IsIdentifierChar(c))
			{
				if (idStart == -1)
					idStart = i;
			}

			bool wasAttribute = false;
			if (!IsIdentifierChar(c) && idStart != -1)
			{
				StringView identifier = GetIdentifier(i);
				switch (identifier)
				{
				case "__attribute__":
					 {
						 //Runtime.FatalError();
						 Runtime.Assert(c == '(');
						 int32 nestDepth = 0;
						 while (i < c_type.Length)
						 {
							 let ac = c_type[i++];
							 if (ac == '(')
								 nestDepth++;
							 if (ac == ')')
								 nestDepth--;

							 if (nestDepth == 0)
								 break;
						}
						wasAttribute = true;
					}
				case "enum":
					{
						Runtime.Assert(type.typeString.IsEmpty);
						flags |= .Enum;
					}
				case "struct", "union":
					{
						Runtime.Assert(type.typeString.IsEmpty);
						flags |= .Struct;
					}
				case "signed":
					{
						Runtime.Assert(!unsigned);
						Runtime.Assert(!signed);
						signed = true;
					}
				case "unsigned":
					{
						Runtime.Assert(!unsigned);
						Runtime.Assert(!signed);
						unsigned = true;
					}
				case "const":
					if (type.typeString.IsEmpty)
						type.isConst = true;
				case "volatile":
					{
						Runtime.Assert(!isVolatile);
						isVolatile = true;
					}

				case "long":
					{
						Runtime.Assert(type.typeString.IsEmpty);
						if (isLong)
							type.typeString.Set(identifier);

						isLong = true;
					}
					
				default:
					{
						Runtime.Assert(type.typeString.IsEmpty);
						type.typeString.Set(identifier);
					}
				}
			}

			if (c == '[')
			{
				type.sizedArray ??= new:_parser .(4);
				let length = GetSizedArrayLength();
				type.sizedArray.Add(length);
			}

			// Function ptr definition
			if (c == '(' && !wasAttribute)
			{
				isFunction = true;
			}

			i++;
		}

		if (idStart != -1 && type.typeString.IsEmpty)
		{
			StringView identifier = GetIdentifier((.)c_type.Length);
			type.typeString.Set(identifier);
		}

		if (type.typeString.IsEmpty && isLong)
		{
			type.typeString.Set("long");
		}

		bool isPrimitive = true;
		switch (type.typeString)
		{
		case "bool":
			{
				type.typeString.Set(nameof(bool));
			}
		case "char":
			{
				if (signed)
					type.typeString.Set(nameof(int8));
				else if (unsigned)
					type.typeString.Set(nameof(uint8));
				else
					type.typeString.Set(nameof(c_char));
			}
		case "wchar_t":
			{
				type.typeString.Set(nameof(c_wchar));
			}

		case "char8_t":
			{
				type.typeString.Set(nameof(char8));
			}

		case "char16_t":
			{
				type.typeString.Set(nameof(char16));
			}
		case "char32_t":
			 {
				 type.typeString.Set(nameof(char32));
			}
			
		case "short":
			{
				if (unsigned)
					type.typeString.Set(nameof(c_ushort));
				else
					type.typeString.Set(nameof(c_short));
			}
		case "int":
			{
				if (unsigned)
					type.typeString.Set(nameof(c_uint));
				else
					type.typeString.Set(nameof(c_int));
			}
		case "long":
			{
				if (unsigned)
				{
					if (isLong)
						type.typeString.Set(nameof(c_ulonglong));
					else
						type.typeString.Set(nameof(c_ulong));
				}
				else
				{
					if (isLong)
						type.typeString.Set(nameof(c_longlong));
					else
						type.typeString.Set(nameof(c_long));
				}
			}

		case "size_t":
			{
				Runtime.Assert(!unsigned && !isLong);
				type.typeString.Set(nameof(c_size));
			}

		case "float":
			{
				type.typeString.Set(nameof(float));
			}
		case "double":
			{
				if (isLong)
				{
					Console.WriteLine("Unupported data type 'long double'");
				}

				type.typeString.Set(nameof(double));
			}


		case "intptr_t":
			{
				Runtime.Assert(!unsigned && !isLong);
				type.typeString.Set(nameof(c_intptr));
			}
		case "uintptr_t":
			{
				Runtime.Assert(!unsigned && !isLong);
				type.typeString.Set(nameof(c_uintptr));
			}

		case "uint8_t", "uint16_t", "uint32_t", "uint64_t",
			 "int8_t", "int16_t", "int32_t", "int64_t":
			{
				type.typeString.Set(_);
				type.typeString.RemoveFromEnd(2);
			}

		default:
			isPrimitive = false;
		}


		Runtime.Assert(type.typeString.Length > 0);

		if (isFunction)
		{
			Runtime.Assert(c_type[i] == '*');
			Runtime.Assert(c_type[++i] == ')');
			Runtime.Assert(c_type[++i] == '(');
			++i;

			// Handle function
			String tmp = scope $"function ";

			Parser.FunctionTypeDef funDef = new:_parser .();
			funDef.typeOnly = true;
			funDef.resultType.raw = type.typeString;
			type.typeDef = funDef;
			WriteBeefType(funDef.resultType, tmp);

			idStart = i;

			void HandleArgType()
			{
				StringView view = c_type[idStart..<i];
				Parser.VariableDecl argDecl = new:_parser .();
				argDecl.type.raw = new:_parser .(view);
				idStart = i + 1;

				if (funDef.args.Count > 0)
					tmp.AppendF(", ");

				WriteBeefType(argDecl.type, tmp);

				funDef.args.Add(argDecl);
			}

			tmp.Append('(');

			while (i < c_type.Length)
			{
				let c = c_type[i];
				if (c == ',')
				{
					HandleArgType();
				}
				else if (c == ')')
				{
					HandleArgType();
					break;
				}

				i++;
			}

			tmp.Append(')');

			type.typeString.Set(tmp);
			
			return flags | .Function;
		}

		if (!isPrimitive)
		{
			if (_parser._aliasMap.TryGetValue(type.typeString, let alias))
			{
				if (!alias.flags.HasFlag(.Resolved))
				{
					alias.flags |= .Resolved;
					alias.flags |= ResolveBeefType(alias.alias);
				}

				if (alias.flags.HasFlag(.Primitive) && !alias.flags.HasFlag(.ForceGenerate))
				{
					bool shouldReplace = true;
					if (onPrimitiveTypeResolve != null)
						shouldReplace = onPrimitiveTypeResolve(type, alias);

					if (shouldReplace)
						type.typeString.Set(alias.alias.typeString);
					else
					{
						alias.flags |= .ForceGenerate;
					}
				}
			}
		}
		else
		{
			flags |= .Primitive;
		}	

		Runtime.Assert(!type.isRef);
		Runtime.Assert(type.typeString.Length > 0);
		return flags;
	}

	void WriteBeefType(Parser.TypeRef type, String buffer)
	{
		StringStream ss = scope .(buffer, .Reference);
		ss.Position = buffer.Length;
		StreamWriter writer = scope .(ss, System.Text.Encoding.UTF8, 64);
		WriteBeefType(type, writer);
	}

	void WriteBeefType(Parser.TypeRef type, StreamWriter writer)
	{
		if (type.typeString.IsEmpty)
			ResolveBeefType(type);

		writer.Write(type.typeString);

		if (type.sizedArray != null)
		{
			for (let dimm in type.sizedArray)
				writer.Write($"[{dimm}]");
		}

		for (int32 _ in 0..<type.ptrDepth)
			writer.Write("*");
	}

	Result<void> GetEnumTypeInfo(Parser.EnumDef e, String prefix, out bool hasDupes)
	{
		hasDupes = false;

		HashSet<String> dups = scope .(e.values.Count);
		for (let v in e.values)
		{
			if (v.value.Length > 0 && !dups.Add(v.value))
			{
				hasDupes = true;
				break;
			}	
		}

		return .Ok;
	}

	void GenerateEnum(Parser.EnumDef e, StreamWriter writer)
	{
		String baseType = "c_int";

		if (e.baseType != null)
		{
			Runtime.NotImplemented();
		}

		String valueNamePrefix = scope .();
		GetEnumTypeInfo(e, valueNamePrefix, let hasDupes);
		
		List<String> attrs = scope .(4);
		if (hasDupes)
			attrs.Add("AllowDuplicates");
		WriteAttrs(attrs, writer);

		WriteIndent(writer);
		writer.WriteLine($"public enum {e.name} : {baseType}");
		WriteIndent(writer);
		writer.WriteLine("{");

		PushIndent();
		for (let v in e.values)
		{
			WriteIndent(writer);
			WriteIdentifier(v.name, writer);
			if (v.value.Length > 0)
			{
				writer.Write(" = ");
				writer.Write(v.value);
			}
			writer.WriteLine(",");
		}
		PopIndent();

		WriteIndent(writer);
		writer.WriteLine("}");

		_createdTypes.Add(e.name);
	}

	void GenerateStruct(Parser.StructTypeDef s, StreamWriter writer)
	{
		Runtime.Assert(s.tag == .Union || s.tag == .Struct);

		List<String> attrs = scope .(4);

		if (s.name == "crypto_hash_sha512_state")
			NOP!();

		attrs.Add("CRepr");
		if (s.tag == .Union)
			attrs.Add("Union");

		WriteAttrs(attrs, writer);
		WriteIndent(writer);
		writer.WriteLine($"public struct {s.name}");
		WriteIndent(writer);
		writer.WriteLine("{");

		PushIndent();

		if (s.innerTypes != null)
		{
			for (let t in s.innerTypes)
			{
				if (let sDef = t as Parser.StructTypeDef)
					GenerateStruct(sDef, writer);
			}
		}

		for (let f in s.fields)
		{
			WriteIndent(writer);
			writer.Write("public ");
			WriteBeefType(f.type, writer);
			writer.Write(" ");
			WriteIdentifier(f.name, writer);
			writer.WriteLine(";");
		}
		PopIndent();
		WriteIndent(writer);
		writer.WriteLine("}");

		_createdTypes.Add(s.name);
	}

	void GenerateFunction(Parser.FunctionTypeDef f, StreamWriter writer)
	{
		List<String> attrs = scope .(4);
		if (!f.typeOnly)
			attrs.Add("CLink");
		attrs.Add("CallingConvention(.Cdecl)");

		WriteAttrs(attrs, writer);
		WriteIndent(writer);
		if (f.typeOnly)
		{
			writer.Write("public function ");
		}
		else
		{
			writer.Write("public static extern ");
		}
		WriteBeefType(f.resultType, writer);
		writer.Write($" {f.name}(");

		for (let a in f.args)
		{
			if (@a.Index != 0)
				writer.Write(", ");

			WriteBeefType(a.type, writer);
			writer.Write(" ");
			WriteIdentifier(a.name, writer);
		}

		writer.WriteLine(");");

	}

	void GenerateAlias(Parser.TypeAliasDef f, StreamWriter writer)
	{
		writer.Write($"public typealias {f.name} = ");
		WriteBeefType(f.alias, writer);
		writer.WriteLine(";");
	}

	EDefineType GetDefineValueType(StringView value)
	{
		var value;
		value.Trim();
		if (value.IsEmpty)
			return .Empty;

		let c = value[0];

		if (c == '"')
			return .String;

		if (c.IsDigit || c == '-' || c == '+')
		{
			int32 longLong = 0;
			for (int32 i < 2)
			{
				if (value.EndsWith("l", .InvariantCultureIgnoreCase))
				{
					longLong++;
					value.RemoveFromEnd(1);
				}
			}

			let explicitUnsigned = value.EndsWith("u", .InvariantCultureIgnoreCase);
			if (explicitUnsigned)
				value.RemoveFromEnd(1);

			if (uint.Parse(value, .AllowHexSpecifier | .AllowLeadingSign) case .Ok(let val))
			{
				if (c == '-')
				{
					Runtime.Assert(!explicitUnsigned);
					return .Int;
				}

				return .UInt;
			}

			if (!explicitUnsigned && int.Parse(value, .AllowHexSpecifier | .AllowLeadingSign) case .Ok(let val))
			{
				return .Int;
			}

			let explicitFloat = value.EndsWith('f');

			if (float.Parse(value..TrimEnd('f')) case .Ok)
				return explicitFloat ? .Float : .Double;
		}

		return .Unknown;
	}

	public void Generate(PreprocParser preproc, Parser parser, StringView _namespace, Stream stream)
	{
		_parser = parser;

		StreamWriter sw = scope .(stream, System.Text.UTF8Encoding.UTF8, 4096);

		sw.WriteLine("using System;");
		sw.WriteLine("using System.Interop;");
		sw.WriteLine();
		sw.WriteLine($"namespace {_namespace};");
		sw.WriteLine();

		for (let e in parser._enums)
		{
			GenerateEnum(e, sw);
			sw.WriteLine();
		}

		for (let s in parser._structs)
		{
			GenerateStruct(s, sw);
			sw.WriteLine();
		}

		sw.WriteLine("public static");
		sw.WriteLine("{");
		PushIndent();
		{
			let startPos = stream.Position;
			defer
			{
				if (startPos != stream.Position)
					sw.WriteLine();
			}
			for (let kv in preproc.defines)
			{
				let def = kv.value;

				if (def.args.Count > 0)
					continue;

				if (this.definesFilter != null && definesFilter(def) == false)
					continue;

				let type = GetDefineValueType(def.value);
				String typeString;
				switch (type)
				{
				case .Unknown, .Empty: continue;
				case .Double:
					typeString = nameof(double);
				case .Float:
					typeString = nameof(float);
				case .Int:
					typeString = nameof(int);
				case .UInt:
					typeString = nameof(uint);
				case .String:
					typeString = nameof(String);
				}

				WriteIndent(sw);
				sw.WriteLine($"public const {typeString} {def.name} = {def.value..TrimEnd()};");
			}
		}

		{
			let startPos = stream.Position;
			defer
			{
				if (startPos != stream.Position)
					sw.WriteLine();
			}

			for (let v in parser.globalVars)
			{
				List<String> attrs = scope .(4);

				switch (v.storageKind)
				{
				case .Extern:
					{
						attrs.Add("CLink");
						WriteAttrs(attrs, sw);
						WriteIndent(sw);
						sw.Write("public static extern ");
						WriteBeefType(v.type, sw);
						sw.WriteLine($" {v.name};");
					}

				case .Unknown:
					{

					}
				}
			}
		}

		for (let f in parser._functions)
 		{
			 if (f.isBuiltIn || f.isConst || f.isMSAlloc || f.isDeprecated)
				 continue;

			 if (f.storageKind != .Extern && !f.HasAttr(.DLLImportAttr))
				 continue;

			 GenerateFunction(f, sw);
			 sw.WriteLine();
		}

		PopIndent();
		sw.WriteLine("}");

		sw.WriteLine();

		for (let kv in parser._aliasMap)
		{
			let def = kv.value;

			if ((def.flags & .ForceGenerate) != .ForceGenerate)
			{
				if ((def.flags & (.Resolved) !=  .Resolved))
					continue;

				if ((def.flags & (.Primitive) == .Primitive))
					continue;
			}
			else
				NOP!();

			if (def.flags & .Function == .Function)
			{
				if (let fn = def.alias.typeDef as Parser.FunctionTypeDef)
				{
					fn.name.Set(def.name);
					GenerateFunction(fn, sw);
				}
				else
				{
					sw.Write($"typealias {def.name} = ");
					WriteBeefType(def.alias, sw);
					sw.WriteLine(";");
				}
				continue;
			}

			if (def.flags.HasFlag(.Struct))
			{
				let created = _createdTypes.ContainsAlt(def.name);

				if (def.name == def.alias.typeString)
				{
					if (!created)
						sw.WriteLine($"struct {def.name};");
				}
				else
				{
					let createdAlias = _createdTypes.ContainsAlt(def.alias.typeString);

					if (!createdAlias)
					{
						sw.WriteLine($"struct {def.alias.typeString};");
					}
					
					sw.Write($"typealias {def.name} = ");
					WriteBeefType(def.alias, sw);
					sw.WriteLine(";");
				}

				continue;
			}

			if (def.flags & (.Enum | .Struct | .Function) == 0)
			{
				sw.Write($"typealias {def.name} = ");
				WriteBeefType(def.alias, sw);
				sw.WriteLine(";");
			}

			//GenerateAlias(def, sw);
		}
	}
}
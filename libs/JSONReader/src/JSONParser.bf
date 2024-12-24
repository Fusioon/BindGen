using System;
using System.Collections;

using internal JSONReader;

namespace System
{
	extension BumpAllocator : ITypedAllocator
	{
#if !BF_ENABLE_REALTIME_LEAK_CHECK
		public void* AllocTyped(Type type, int size, int align) => Alloc(size, align);
#endif
	}
}


namespace JSONReader
{
	class JSONParser : JSONParser<BumpAllocator>
	{
		append BumpAllocator _alloc = .(.Allow);
		public override void* AllocTyped(Type type, int size, int align) => _alloc.AllocTyped(type, size, align);

		public this() : base(_alloc, false)
		{

		}
	}

	class JSONParser<TAlloc> : ITypedAllocator
		where TAlloc : IRawAllocator
	{
		const char8 ARRAY_START = '[';
		const char8 ARRAY_END = ']';
		const char8 OBJECT_START = '{';
		const char8 OBJECT_END = '}';

		TAlloc _alloc;
		append List<JValue> _parsedValues = .(8);
		bool _needsDelete;

		public void* Alloc(int size, int align) => _alloc.Alloc(size, align);
		public virtual void* AllocTyped(Type type, int size, int align) => Alloc(size, align);

		public void Free(void* ptr) => _alloc.Free(ptr);

		public this(TAlloc alloc, bool needsDelete)
		{
			_alloc = alloc;
			_needsDelete = needsDelete;
		}

		public ~this()
		{
			if (!_needsDelete)
				return;

			for (let v in _parsedValues)
			{
				v.Free(this);
			}
		}

		void SkipWhitespace(StringView text, ref int i)
		{
			while (i < text.Length)
			{
				if (!text[i].IsWhiteSpace)
					break;

				i++;
			}
		}

		public Result<JValue> Parse(StringView text)
		{
			int i = 0;
			SkipWhitespace(text, ref i);

			if (i >= text.Length)
			{
				return .Err;
			}
			switch (text[i])
			{
			case OBJECT_START:
				{
					i++;
					let obj = new:this JObject();
					switch (ParseObject(text, ref i, obj))
					{
					case .Ok:
						{
							_parsedValues.Add(.OBJECT(obj));
							return .Ok(.OBJECT(obj));
						}
					case .Err:
						delete:this obj;
					}
				}
			case ARRAY_START:
				{
					i++;
					let arr = new:this JArray();
					switch (ParseArray(text, ref i, arr))
					{
					case .Ok:
						{
							_parsedValues.Add(.ARRAY(arr));
							return .Ok(.ARRAY(arr));
						}
					case .Err:
						delete:this arr;
					}
				}
			}

			return .Err;
		}

		Result<void> ParseObject(StringView text, ref int i, JObject target)
		{
			SkipWhitespace(text, ref i);

			if (i < text.Length && text[i] == OBJECT_END)
			{
				i++;
				return .Ok;
			}

			LOOP: while (i < text.Length)
			{
				if (ParsePair(text, ref i) case .Ok((let key, let val)))
				{
					target.AddValue(key, val);
				}
				else
					return .Err;

				SkipWhitespace(text, ref i);

				if(i >= text.Length)
					break LOOP;

				switch (text[i])
				{
				case OBJECT_END: i++; return .Ok;
				case ',': i++;
				default: break LOOP;
				}

				SkipWhitespace(text, ref i);
			}

			return .Err;
		}

		Result<(String key, JValue val)> ParsePair(StringView text, ref int i)
		{
			SkipWhitespace(text, ref i);
			let key = new:this String();

			ERROR_CLEANUP:do
			{
				if (ParseString(text, ref i, key) case .Err)
					break ERROR_CLEANUP;

				SkipWhitespace(text, ref i);
				if(i >= text.Length || text[i] != ':')
					break ERROR_CLEANUP;

				i++;

				SkipWhitespace(text, ref i);

				switch (ParseValue(text, ref i))
				{
				case .Ok(let val):
					return .Ok((key, val));

				case .Err:
					break;
				}

				break ERROR_CLEANUP;
			}

			delete:this key;
			return .Err;
		}

		Result<void> ParseString(StringView text, ref int i, String buffer)
		{
			// @TODO - support escaped characters
			SkipWhitespace(text, ref i);
			if (i >= text.Length)
				return .Err;

			if (text[i] != '"')
				return .Err;

			i++;// Skip " char
			char8 lc = 0;
			while (i < text.Length)
			{
				let c = text[i];

				if (lc == '\\')
				{
					switch(c)
					{
					case 'n': buffer[buffer.Length - 1] = ('\n');
					case '\\': buffer[buffer.Length - 1] = ('\\');
					case 'r': buffer[buffer.Length-1] = ('\r');
					case 't': buffer[buffer.Length-1] = ('\t');
					case '"': buffer[buffer.Length-1] = ('"');
					default:
						return .Err;
					}
					lc = 0;
					i++;
					continue;
				}
				else if (c == '"')
				{
					i++;
					//Console.WriteLine(lc);
					return .Ok;
				}	

				buffer.Append(c);
				lc = c;
				i++;
			}

			return .Err;

			/*if (i >= start)
			{
				buffer.Append(text, start, i - start);
				i++;// Skip " char
				return .Ok;
			}

			return .Err;*/
		}

		Result<JValue> ParseValue(StringView text, ref int i)
		{
			SkipWhitespace(text, ref i);
			if (i >= text.Length)
				return .Err;

			let c = text[i];

			switch (c)
			{
			case OBJECT_START:
				{
					i++;
					let obj = new:this JObject();
					switch (ParseObject(text, ref i, obj))
					{
					case .Ok: return .Ok(.OBJECT(obj));
					case .Err:
						{
							delete:this obj;
							return .Err;
						}
					}
				}
			case ARRAY_START:
				{
					i++;
					let arr = new:this JArray();
					switch (ParseArray(text, ref i, arr))
					{
					case .Ok: return .Ok(.ARRAY(arr));
					case .Err:
						{
							delete:this arr;
							return .Err;
						}
					}
				}
			case '"':
				{
					let str = new:this String();
					switch (ParseString(text, ref i, str))
					{
					case .Ok: return .Ok(.STRING(str));
					case .Err:
						{
							delete:this str;
							return .Err;
						}
					}
				}
			}

			if (c.IsDigit || c == '+' || c == '-')
			{
				return ParseNumber(text, ref i);
			}

			let token = GetToken(text, ref i);

			switch (token)
			{
			case "true": return .Ok(.BOOL(true));
			case "false": return .Ok(.BOOL(false));
			case "null": return .Ok(.NULL);
			}

			return .Err;
		}

		StringView GetToken(StringView text, ref int i)
		{
			let start = i;
			while (i < text.Length)
			{
				let c = text[i];
				if (!c.IsLetter)
					break;

				i++;
			}

			if (i > start)
				return .(text, start, i - start);

			return StringView();
		}

		Result<JValue> ParseNumber(StringView text, ref int i)
		{
			int8 sign = 1;

			switch(text[i])
			{
			case '-': sign = -1; fallthrough;
			case '+': i++;
			default: break;
			}

			var start = i;

			uint64 value = 0;
			bool floating = false;
			VALUE_LOOP: while(i < text.Length)
			{
				let c = text[i];
				if(c.IsDigit)
				{
					value *= 10;
					value += (.)(c - '0');
				}
				else if(c == '.')
				{
					floating = true;
					i++;
					break VALUE_LOOP;
				}
				else
					break VALUE_LOOP;

				i++;
			}

			if(start == i)
				return .Err;

			if(!floating)
				return .Ok(.INT64(sign * (int64)value));

			uint64 decimal = 0;
			bool hasExponent = false;
			start = i;
			uint32 startingZeroes = 0;
			DECIMAL_LOOP: while(i < text.Length)
			{
				let c = text[i];
				if(c.IsDigit)
				{
					decimal *= 10;
					decimal += (.)(c - '0');
					if (decimal == 0)
						startingZeroes++;
				}
				else if(c == 'e' || c == 'E')
				{
					hasExponent = true;
					i++;
					break DECIMAL_LOOP;
				}
				else
					break DECIMAL_LOOP;

				i++;
			}

			if(start == i)
				return .Err;

			double doubleVal = decimal;
			while(doubleVal >= 1)
				doubleVal /= 10;

			while (startingZeroes-- > 0)
				doubleVal /= 10;

			doubleVal += value;

			if(!hasExponent)
				return .Ok(.DOUBLE(sign + doubleVal));

			bool exponentNegative = false;
			switch(text[i])
			{
			case '-': exponentNegative = true; fallthrough;
			case '+': i++;
			default: break;
			}

			start = i;

			uint64 exponent = 0;

			EXPONENT_LOOP: while(i < text.Length)
			{
				let c = text[i];
				if(c.IsDigit)
				{
					exponent *= 10;
					exponent += (.)(c - '0');
				}
				else
					break EXPONENT_LOOP;

				i++;
			}

			if(start == i)
				return .Err;

			uint64 exponentMult = 1;
			while(exponent-- > 0)
			{
				exponentMult *= 10;
			}	

			if(exponentNegative)
				doubleVal /= exponentMult;
			else
				doubleVal *= exponentMult;

			return .Ok(.DOUBLE(sign * doubleVal));
		}

		Result<void> ParseArray(StringView text, ref int i, JArray target)
		{
			SkipWhitespace(text, ref i);

			if(i < text.Length && text[i] == ARRAY_END)
			{
				i++;
				return .Ok;
			}

			LOOP: while(i < text.Length)
			{
				switch(ParseValue(text, ref i))
				{
				case .Ok(let val): target.AddValue(val);
				case .Err:
					NOP!();
				}

				SkipWhitespace(text, ref i);

				if(i >= text.Length)
					continue;

				switch(text[i])
				{
				case ARRAY_END: i++; return .Ok;
				case ',': i++;
				default: break LOOP;
				}

				SkipWhitespace(text, ref i);

			}

			return .Err;
		}
	}
}

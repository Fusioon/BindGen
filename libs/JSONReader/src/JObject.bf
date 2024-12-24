using System;
using System.Collections;

namespace JSONReader
{
	class JObject : IEnumerable<(String key, JValue value)>
	{
		public void Free<TAlloc>(TAlloc alloc) where TAlloc : IRawAllocator, class
		{
			for (let v in _values)
			{
				v.value.Free(alloc);
				delete:alloc v.key;
			}
			_values.Clear();
		}

		append Dictionary<String, JValue> _values;
		public int Count => _values.Count;
		public bool IsEmpty => _values.IsEmpty;

		public Result<JValue> this[StringView key]
		{
			get
			{
				if(_values.TryGetAlt(key, let matchKey, let val))
				{
					return .Ok(val);
				}
				return .Err;
			}
		}

		internal void AddValue(String key, JValue val)
		{
			_values.Add(key, val);
		}

		internal void AddValue(StringView key, JValue val)
		{
			_values.Add(new .(key), val);
		}

		public Dictionary<String, JValue>.Enumerator GetEnumerator()
		{
			return _values.GetEnumerator();
		}
	}
}

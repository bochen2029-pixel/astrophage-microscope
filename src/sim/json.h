// src/sim/json.h -- a tiny dependency-free JSON (jsonc) reader for scenarios/*.json.
//
// Hand-rolled rather than taking a dependency (Iron Rule 8): the scenario schema is
// fixed and small, so a recursive-descent reader is ~200 lines and buys us out of an
// ADR. Supports objects, arrays, strings (with the standard escapes; \uXXXX below 0x80
// only), numbers (int/float/exp via strtod), true/false/null, and `//` and `/* */`
// comments -- the docs/SCENARIOS.md example is jsonc. Host-only; no exceptions cross a
// boundary (strtod, not stod). It is permissive on input and strict only at the point
// the loader reads a typed field.
#pragma once

#include <cstdlib>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

namespace astro::json {

struct Value {
    enum class Type { Null, Bool, Number, String, Array, Object };
    Type type = Type::Null;
    bool boolean = false;
    double number = 0.0;
    std::string str;
    std::vector<Value> arr;
    std::vector<std::pair<std::string, Value>> obj;

    bool is_null()   const { return type == Type::Null; }
    bool is_object() const { return type == Type::Object; }
    bool is_array()  const { return type == Type::Array; }
    bool is_number() const { return type == Type::Number; }
    bool is_string() const { return type == Type::String; }

    // Object lookup; nullptr if not an object or the key is absent.
    const Value* find(const char* key) const {
        if (type != Type::Object) return nullptr;
        for (const auto& kv : obj)
            if (kv.first == key) return &kv.second;
        return nullptr;
    }

    // Scalar reads with a default when the field is the wrong type.
    double      num_or(double d)      const { return type == Type::Number ? number : d; }
    bool        bool_or(bool d)       const { return type == Type::Bool ? boolean : d; }
    std::string str_or(const char* d) const { return type == Type::String ? str : std::string(d); }

    // Object field convenience: value-or-default when the key is missing.
    double num(const char* key, double d) const {
        const Value* v = find(key); return v ? v->num_or(d) : d;
    }
    bool flag(const char* key, bool d) const {
        const Value* v = find(key); return v ? v->bool_or(d) : d;
    }
    std::string text(const char* key, const char* d) const {
        const Value* v = find(key); return v ? v->str_or(d) : std::string(d);
    }
    size_t size() const {
        return type == Type::Array ? arr.size() : (type == Type::Object ? obj.size() : 0);
    }
};

class Parser {
public:
    explicit Parser(const std::string& text) : s_(text) {}

    bool parse(Value& out, std::string& err) {
        skip_ws();
        if (!value(out)) { err = err_; return false; }
        skip_ws();
        if (pos_ != s_.size()) { fail("trailing content"); err = err_; return false; }
        return true;
    }

private:
    const std::string& s_;
    size_t pos_ = 0;
    std::string err_;

    bool fail(const char* what) {
        if (err_.empty())
            err_ = std::string("json: ") + what + " at offset " + std::to_string(pos_);
        return false;
    }

    void skip_ws() {
        for (;;) {
            while (pos_ < s_.size() &&
                   (s_[pos_] == ' ' || s_[pos_] == '\t' || s_[pos_] == '\n' || s_[pos_] == '\r'))
                ++pos_;
            if (pos_ + 1 < s_.size() && s_[pos_] == '/' && s_[pos_ + 1] == '/') {
                pos_ += 2;
                while (pos_ < s_.size() && s_[pos_] != '\n') ++pos_;
            } else if (pos_ + 1 < s_.size() && s_[pos_] == '/' && s_[pos_ + 1] == '*') {
                pos_ += 2;
                while (pos_ + 1 < s_.size() && !(s_[pos_] == '*' && s_[pos_ + 1] == '/')) ++pos_;
                if (pos_ + 1 < s_.size()) pos_ += 2;
            } else {
                break;
            }
        }
    }

    bool match(const char* lit) {
        const size_t n = std::strlen(lit);
        if (s_.compare(pos_, n, lit) == 0) { pos_ += n; return true; }
        return false;
    }

    bool value(Value& v) {
        skip_ws();
        if (pos_ >= s_.size()) return fail("unexpected end");
        const char c = s_[pos_];
        if (c == '{') return object(v);
        if (c == '[') return array(v);
        if (c == '"') { v.type = Value::Type::String; return string(v.str); }
        if (c == '-' || (c >= '0' && c <= '9')) return number(v);
        if (match("true"))  { v.type = Value::Type::Bool; v.boolean = true;  return true; }
        if (match("false")) { v.type = Value::Type::Bool; v.boolean = false; return true; }
        if (match("null"))  { v.type = Value::Type::Null; return true; }
        return fail("unexpected token");
    }

    bool object(Value& v) {
        v.type = Value::Type::Object;
        ++pos_;  // consume '{'
        skip_ws();
        if (pos_ < s_.size() && s_[pos_] == '}') { ++pos_; return true; }
        for (;;) {
            skip_ws();
            if (pos_ >= s_.size() || s_[pos_] != '"') return fail("expected object key");
            std::string key;
            if (!string(key)) return false;
            skip_ws();
            if (pos_ >= s_.size() || s_[pos_] != ':') return fail("expected ':'");
            ++pos_;
            Value child;
            if (!value(child)) return false;
            v.obj.emplace_back(std::move(key), std::move(child));
            skip_ws();
            if (pos_ >= s_.size()) return fail("unterminated object");
            if (s_[pos_] == ',') { ++pos_; continue; }
            if (s_[pos_] == '}') { ++pos_; return true; }
            return fail("expected ',' or '}'");
        }
    }

    bool array(Value& v) {
        v.type = Value::Type::Array;
        ++pos_;  // consume '['
        skip_ws();
        if (pos_ < s_.size() && s_[pos_] == ']') { ++pos_; return true; }
        for (;;) {
            Value child;
            if (!value(child)) return false;
            v.arr.push_back(std::move(child));
            skip_ws();
            if (pos_ >= s_.size()) return fail("unterminated array");
            if (s_[pos_] == ',') { ++pos_; continue; }
            if (s_[pos_] == ']') { ++pos_; return true; }
            return fail("expected ',' or ']'");
        }
    }

    bool string(std::string& out) {
        ++pos_;  // consume opening '"'
        out.clear();
        while (pos_ < s_.size()) {
            const char c = s_[pos_++];
            if (c == '"') return true;
            if (c != '\\') { out.push_back(c); continue; }
            if (pos_ >= s_.size()) break;
            const char e = s_[pos_++];
            switch (e) {
                case '"':  out.push_back('"');  break;
                case '\\': out.push_back('\\'); break;
                case '/':  out.push_back('/');  break;
                case 'n':  out.push_back('\n'); break;
                case 't':  out.push_back('\t'); break;
                case 'r':  out.push_back('\r'); break;
                case 'b':  out.push_back('\b'); break;
                case 'f':  out.push_back('\f'); break;
                case 'u': {
                    if (pos_ + 4 > s_.size()) return fail("bad \\u escape");
                    int cp = 0;
                    for (int k = 0; k < 4; ++k) {
                        const char h = s_[pos_++];
                        cp <<= 4;
                        if (h >= '0' && h <= '9')      cp |= h - '0';
                        else if (h >= 'a' && h <= 'f') cp |= h - 'a' + 10;
                        else if (h >= 'A' && h <= 'F') cp |= h - 'A' + 10;
                        else return fail("bad \\u hex");
                    }
                    out.push_back(cp < 0x80 ? static_cast<char>(cp) : '?');
                    break;
                }
                default: return fail("bad string escape");
            }
        }
        return fail("unterminated string");
    }

    bool number(Value& v) {
        const char* begin = s_.c_str() + pos_;
        char* end = nullptr;
        const double d = std::strtod(begin, &end);
        if (end == begin) return fail("bad number");
        pos_ += static_cast<size_t>(end - begin);
        v.type = Value::Type::Number;
        v.number = d;
        return true;
    }
};

// Parse `text`; on failure returns a Null value and fills `err`.
inline Value parse(const std::string& text, std::string& err) {
    Value v;
    Parser p(text);
    if (!p.parse(v, err)) v = Value{};
    return v;
}

} // namespace astro::json

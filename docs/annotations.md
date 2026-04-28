# 📝 FroggyDocs Annotations Guide

Add annotations directly in your API code files. FroggyDocs parses these to generate OpenAPI documentation.

---

## Basic Annotations

### @api - Define Endpoint (Required)
```javascript
// @api GET /users
// @api POST /api/users
// @api PUT /api/users/:id
// @api DELETE /api/users/:id
// @api PATCH /api/users/:id
```

**Format:** `@api <METHOD> <PATH>`

**Supported Methods:**
- `GET`
- `POST`
- `PUT`
- `PATCH`
- `DELETE`
- `HEAD`
- `OPTIONS`

---

### @desc - Description
```javascript
// @desc Get all users from the database
```

---

### @tag - Category/Group
```javascript
// @tag Users
// @tag Auth
// @tag Admin
```
Multiple tags are supported:
```javascript
// @tag Users
// @tag Auth
```

---

## Request Body

### @body - Field Definition
```javascript
// @body name string User's full name
// @body email string User's email address
// @body age number User's age
// @body isActive boolean Account status
```

**Format:** `@body <field_name> <type> <description>`

**Supported Types:**
- `string`
- `number`
- `boolean`
- `array`
- `object`

---

### @body-json - Inline JSON
```javascript
// @body-json
// {
//   "company": "Acme Inc",
//   "employees": 50,
//   "active": true
// }
```

---

### @body-file - From JSON File
```javascript
// @body-file ./schemas/user.json
```

---

## Authentication

### @auth - Requires Authentication
```javascript
// @auth
```
Adds security requirement to the endpoint.

---

## Examples

### Complete Example (JavaScript/Node.js)
```javascript
// @api POST /api/users
// @tag Users
// @tag Auth
// @desc Create a new user account
// @body name string User's full name
// @body email string User's email address
// @body password string User's password
// @auth
app.post('/api/users', async (req, res) => {
  // Your API logic here
});
```

### Python Example
```python
# @api GET /users
# @tag Users
# @desc Get all users
def get_users():
    # Your API logic here
    pass
```

### Go Example
```go
// @api GET /users
// @tag Users
// @desc Get all users
func GetUsers(w http.ResponseWriter, r *http.Request) {
    // Your API logic here
}
```

### Dart/Flutter Example
```dart
// @api GET /users
// @tag Users
// @desc Get all users
Future<List<User>> getUsers() async {
  // Your API logic here
}
```

---

## Language Support

| Language | Comment Style | Extensions |
|----------|--------------|-------------|
| JavaScript/TypeScript | `//` | `.js`, `.ts`, `.jsx`, `.tsx` |
| Dart | `//` | `.dart` |
| Python | `#` | `.py` |
| Ruby | `#` | `.rb` |
| Go | `//` | `.go` |
| Rust | `//` | `.rs` |
| Java/Kotlin | `//` | `.java`, `.kt` |
| PHP | `//` | `.php` |
| C# | `//` | `.cs` |
| C/C++ | `//` | `.c`, `.cpp`, `.h` |

---

## Output

FroggyDocs generates [OpenAPI 3.0](https://spec.openapis.org/oas/v3.0.0) specification that can be:
- Viewed in the built-in web UI
- Imported into Swagger UI
- Used with other OpenAPI tools
- Exported as JSON or YAML
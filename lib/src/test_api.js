// @api GET /api/simple
// @tag Users
// @desc Simple setup using method 1
// @body title String Post title
// @body views Number Total views count
app.post('/api/simple', (req, res) => {});

// @api GET /api/me
// @tag Users
// @desc Extracting from external file called mock.json using method 2
// @body-file ./mock.json
app.post('/api/me', (req, res) => {});

// @api PUT /api/inline-json
// @tag Users
// @desc Extracting from inline JSON block using method 3
app.put('/api/inline-json', (req, res) => {
    res.json({
        "message": "This is an inline JSON response",
    })
});

//@api POST /api/login
//@tag Auth
//@desc User login endpoint with inline JSON body
app.post('/api/login', (req, res) => {
    res.json({
        "token": "abc123",
        "expiresIn": 3600
    });
});

//@api POST /api/register
//@tag Auth
//@desc User registration endpoint with inline JSON body
app.post('/api/register', (req, res) => {
    res.json({
        "message": "User registered successfully",
        "userId": 12345
    });
});

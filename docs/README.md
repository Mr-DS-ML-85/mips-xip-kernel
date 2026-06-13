# Contributing to Documentation

## How to Contribute

1. Fork the repository
2. Create a feature branch: `git checkout -b docs/your-feature`
3. Make your changes
4. Test locally: Open `docs/index.html` in a browser
5. Submit a pull request

## Local Development

No build step required. The documentation is a static HTML site:

```bash
# Open in browser
open docs/index.html

# Or serve with Python
cd docs
python3 -m http.server 8000
# Visit http://localhost:8000
```

## GitHub Pages Deployment

The site is automatically deployed to GitHub Pages when changes are pushed to the `docs/` directory on the main branch.

## Writing Guidelines

- Use clear, concise language
- Include code examples where applicable
- Follow the existing style and formatting
- Test all code snippets before submitting
- Keep sections focused and well-organized

## File Structure

```
docs/
├── index.html      # Main documentation page
├── style.css       # Stylesheet
├── script.js       # Interactive features
├── _config.yml     # GitHub Pages configuration
├── .nojekyll       # Bypass Jekyll processing
└── README.md       # This file
```

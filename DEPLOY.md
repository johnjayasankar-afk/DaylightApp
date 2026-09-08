# Deploying this page

It is a plain static site: HTML, CSS, one JavaScript file and some images.
**There is nothing to build.** Any static host will serve it.

---

## The error you saw

```
404: NOT_FOUND
Code: DEPLOYMENT_NOT_FOUND
```

This is worth reading carefully, because it is **not** "a file is missing from
your site". It means *Vercel has no deployment at the address you opened*. The
page content is not involved.

It has three usual causes:

| Cause | How to tell | Fix |
|---|---|---|
| The deployment failed, so nothing was published | The project exists in the dashboard but every deployment is red / "Error" | Open the failed deployment → **Build Logs** and read the first error |
| You opened a URL that was never a deployment | You typed or guessed the address, or used one from a deleted project | Use the URL the dashboard shows on the project page |
| The deployment was deleted | It used to work | Deploy again |

A missing file inside a *working* deployment gives plain `NOT_FOUND` instead,
with no `DEPLOYMENT_NOT_FOUND` code. So the thing to check first is whether a
deployment succeeded at all — not the files.

---

## The route with the fewest ways to go wrong

The CLI tells you what happened instead of leaving you to guess.

```bash
npm i -g vercel
```

Then, **from inside this folder** (the one containing `index.html`):

```bash
vercel
```

Answer the prompts — accept every default. When it asks
*"In which directory is your code located?"* the answer is `./`.

It prints a URL when it finishes. That URL is the deployment; open that one
rather than anything you construct yourself. When you are happy with it:

```bash
vercel --prod
```

If anything fails, the CLI prints the reason immediately, which is the whole
advantage over the drag-and-drop route.

---

## Or drag and drop

Go to [vercel.com/new](https://vercel.com/new), and drag in **the folder that
contains `index.html`** — not a folder containing that folder, and not the zip.

Vercel should show *Framework Preset: Other* and leave the build settings
empty. That is correct. If it has guessed a framework, change it to **Other**
and clear the Build Command and Output Directory.

Getting this wrong is the most common reason a drag-and-drop deploy "succeeds"
but serves nothing: Vercel publishes a root that contains only a subfolder, so
`/` has no `index.html`.

The right structure at the deployment root is:

```
index.html          <- must be here, at the top level
styles.css
app.js
vercel.json
assets/
downloads/
```

---

## Or from GitHub

Push this folder to a repository and import it at
[vercel.com/new](https://vercel.com/new).

If the page lives in a **subdirectory** of a bigger repository — as it does in
the Daylight repo, at `site/` — set **Root Directory** to that subdirectory in
the project settings. Leaving it at the repository root is the other common way
to get a deployment that builds fine and serves nothing.

---

## If it still will not work

Delete `vercel.json` and deploy again.

Everything in that file is optional — it sets security headers and cache
policy, nothing the page needs to function. If Vercel ever rejects it, the
deployment fails outright, and a failed deployment is exactly what produces
`DEPLOYMENT_NOT_FOUND`. Removing it is a clean way to rule that out in one
step, and the site works identically without it.

## Checking it locally first

Worth doing before blaming the host:

```bash
python3 -m http.server 8000
```

Then open <http://localhost:8000>. If it works there, the files are fine and
the problem is in the deployment configuration rather than the page.

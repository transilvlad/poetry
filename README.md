# Unorthodox brilliance

Every software engineer has to satisfy what the client wants.
Sometimes the client has impossible requirements and an impossibly short deadline.

That's when unorthodox brilliance comes into play.
It's that moment when you realize they want you to turn a 747 into an F16 while it's flying and it's on fire.
That moment say "frak it" and just give them what they want.  

## Search everything
This is a query I wrote to add **search everything** to a project management system that was built by 5 people over 15 years and none of them had a clue what they were doing.
Lucky for me I was able to fiddle with the indexes to optimize the performance, but I was unable to change the schemas given that would require months of code refactoring and I didn't have time for that.
So I improvised and this is what I ended up with.

It did work and it did return everything required for display in one query.

The longest search took about 1.4 seconds to execute.
While this is normally bad, the fortune was the number of concurrent users was under 10.

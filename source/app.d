import vibe.data.json;
import std.file;
import std.stdio;
import std.process;
import std.format;
import std.exception;
import std.algorithm;
import dyaml;

void cleanScratchArea()
{
    if(exists("scratchArea") && isDir("scratchArea"))
        rmdirRecurse("scratchArea");
}

void main()
{
    auto jsonInput = readText("mirror.json");
    auto config = parseJsonString(jsonInput);
    foreach(project; config[])
    {
        auto repo = project["repository"];
        auto name = project["name"].get!string;
        string url;
        switch(repo["kind"].get!string)
        {
        case "github":
            url = format("https://github.com/%s/%s.git", repo["owner"].get!string, repo["project"].get!string);
            break;
        default:
            // skip other projects we don't know how to fetch
            continue;
        }
        cleanScratchArea();
        writeln("Cloning ", name, "...");
        auto cloneResult = execute(["git", "clone", url, "scratchArea"]);
        if(cloneResult.status != 0)
        {
            writeln("Error cloning project ", project["name"].get!string, "; output: ", cloneResult.output);
            continue;
        }

        // loop through all the known configurations, checking dub.json files against dyaml.

        foreach(vers; project["versions"][])
        {
            auto recipeFilename = vers["info"]["packageDescriptionFile"].get!string;
            //if(recipeFilename.endsWith(".json"))
            if(recipeFilename == "dub.json")
            {
                writeln("testing version ", vers["version"].get!string);
                auto checkoutResult = execute(["git",
                                              "--git-dir=./scratchArea/.git",
                                              "--work-tree=./scratchArea",
                                              "checkout",
                                              vers["commitID"].get!string]);
                if(checkoutResult.status != 0)
                {
                    writeln("Error checking out version ", vers["version"].get!string, "; output: ", checkoutResult.output);
                    continue;
                }

                try
                {
                    auto recipeText = readText("scratchArea/" ~ recipeFilename);
                    import std.encoding: getBOM;
                    import std.string: representation;
                    auto bom = recipeText.representation.getBOM;
                    recipeText = recipeText[bom.sequence.length .. $];
                    auto recipe = parseJsonString(recipeText);
                    auto yamlRecipe = Loader.fromString(recipeText).load();
                }
                catch(Exception e)
                {
                    writeln("failed to parse: ", e.msg);
                }
            }
        }
        //break;
    }
}

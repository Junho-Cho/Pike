#include "types.h"

static private int verify_any(SGML data, string in)
{
  int i=1;
  foreach(data,mixed x)
  {
    if(objectp(x))
    {
      if(strlen(x->tag) && x->tag[0]=='/')
      {
	werror("Unmatched "+x->tag+" near pos "+x->pos+"\n");
	werror(in);
	i=0;
	continue;
      }
      switch(x->tag)
      {
      default:
	werror("Unknown tag "+x->tag+" near pos "+x->pos+".\n");
	werror(in);
	i=0;
	break;

      case "font":
      case "firstpage":
      case "preface":
      case "introduction":

      case "chapter":
      case "appendix":
      case "i":
      case "b":
      case "a":
      case "anchor":
      case "tt":
      case "pre":
      case "tr":
      case "td":
      case "table":
      case "box":
      case "h1":
      case "h2":
      case "h3":
      case "dl":
      case "ul":
      case "section":
      case "center":
      case "ol":
      case "encaps":
      case "th":
      case "illustration":
      case "strong":
      case "link":

	case "man_nb":
	case "module":
	case "class":
	case "method":
	case "function":
	case "man_description":
	case "man_see":
	case "man_syntax":
	case "man_bugs":
	case "man_example":
	case "man_title":

      case "ex_identifier":
      case "ex_keyword":
      case "ex_string":
      case "ex_comment":
      case "example":
	if(!x->data)
	{
	  werror("Tag "+x->tag+" not closed near pos "+x->pos+".\n");
	  werror(in);
	  i=0;
	}

	break;

      case "ex_indent":
      case "ex_br":
      case "dt":
      case "dd":
      case "li":
      case "ref":
      case "hr":
      case "br":
      case "img":
      case "image":
      case "table-of-contents":
      case "index":
	if(x->data)
	{
	  werror("Tag "+x->tag+" should not be closed near pos "+x->pos+"\n");
	  werror(in);
	  i=0;
	}
      case "p":
      }

      if(x->data)
	if(!verify_any(x->data,"  In tag "+x->tag+" near pos "+x->pos+"\n"+in))
	  i=0;
    }
  }
  return i;
}

int verify(SGML data)
{
  return verify_any(data,"");
}

int islink(string tag)
{
  switch(tag)
  {
  case "anchor":
  case "chapter":
  case "preface":
  case "introduction":
  case "section":
  case "table":
  case "appendix":
  case "image":
  case "illustration":
    return 1;
  }
}

INDEX_DATA collect_index(SGML data, void|INDEX_DATA index,void|mapping taken)
{
  if(!index) index=([]);
  if(!taken) taken=([]);

  foreach(data,TAG data)
  {
    if(objectp(data))
    {
      if(islink(data->tag))
      {
	if(string real_name=data->params->name)
	{
	  string new_name=real_name;
	  
	  if(taken[new_name])
	  {
	    int n=2;
//	    werror("Warning, duplicate "+real_name+" near pos "+data->pos+".\n");
	    while(taken[new_name+"_"+n]) n++;
	    new_name+="_"+n;
	  }
	  taken[new_name]++;
	  data->params->name=new_name;
	  
	  if(index[real_name])
	  {
	    index[real_name]+=({new_name});
	  }else{
	    index[real_name]=({new_name});
	  }
	}
      }
      if(data->data)
	collect_index(data->data,index,taken);
    }
  }
  return index;
}

INDEX newind;
INDEX_DATA index;

static private void build_index(string from, string fullname)
{
  mapping m=newind;

  if(string *to=index[fullname])
  {
    foreach(from/".",string tmp)
      {
	if(mapping m2=m[tmp])
	  m=m2;
	else
	  m=m[tmp]=([]);
      }
    if(!m[0]) m[0]=([]);
    m[0][fullname]=to;
  }
}

INDEX group_index(INDEX_DATA i)
{
  newind=([]);
  index=i;
  foreach(indices(index),string real_name)
  {
    string *to=index[real_name];
    build_index(real_name,real_name);
    string *from=real_name/".";
    for(int e=1;e<sizeof(from);e++)
      build_index(from[e], from[..e]*".");
  }
  index=0;
  return newind;
}

INDEX group_index_by_character(INDEX i)
{
  mapping m=([]);
  foreach(indices(i),string key)
    {
      int c;
      sscanf(lower_case(Html.unquote_param(key)),"%*[_ ]%c",c);
      string char=upper_case(sprintf("%c",c));
//      werror(char +" : "+key+"\n");
      if(!m[char]) m[char]=([]);
      m[char][key]=i[key];
    }
  return m;
}

multiset reserved_pike =
(<
  "array","break","case","catch","continue","default","do","else","float",
  "for","foreach","function","gauge","if","inherit","inline","int","lambda",
  "mapping","mixed","multiset","nomask","object","predef","private","program",
  "protected","public","return","sscanf","static","string","switch","typeof",
  "varargs","void","while"
>);

multiset reserved_c =
(<
  "break","case","continue","default","do","else","float","double",
  "for","if","int","char","short","unsigned","long",
  "public","return","static","switch",
  "void","while"
>);

object(Sgml.Tag) parse_pike_code(string x, int pos, multiset(string) reserved)
{
  int p,e;
  int tabindented=-1;
  SGML ret=({""});

  while(e<strlen(x) && (x[e]=='\t' || x[e]=='\n' || x[e]==' ')) e++;
  while(e && (e>=strlen(x) || x[e]!='\n')) e--;

  for(;e<strlen(x);e++)
  {
    switch(x[e])
    {
    case '_':
    case 'a'..'z':
    case 'A'..'Z':
    {
      p=e;
      
      while(1)
      {
	switch(x[++e])
	{
	case '_':
	case 'a'..'z':
	case 'A'..'Z':
	case '0'..'9':
	  continue;
	}
	break;
      }
      
      string id=x[p..--e];
      if(reserved[id])
	ret+=({ Sgml.Tag("ex_keyword",([]), pos+e, ({ id }) ) });
      else
	ret+=({ Sgml.Tag("ex_identifier",([]), pos+e, ({ id }) ) });
      break;
    }
    
    
    case '\'':
      p=e;
      while(x[++e]!='\'')
	if(x[e]=='\\')
	  e++;
      ret+=({ Sgml.Tag("ex_string",([]), pos+e, ({ x[p..e]}) ) }); 
      break;
      
    case '"':
      p=e;
      while(x[++e]!='"')
	if(x[e]=='\\')
	  e++;
      
      ret+=({ Sgml.Tag("ex_string",([]), pos+e, ({ x[p..e] }) ) });
      break;

    case '\n':
      if(tabindented!=-1)
	ret+=({ Sgml.Tag("ex_br", ([]), pos+e) });

      if(tabindented)
      {
	for(int y=1;y<9;y++)
	{
	  switch(x[e+y..e+y])
	  {
	  case " ": continue;
	  case "\t": e+=y;
	    tabindented=1;
	  default:
	  }
	  break;
	}
	if(tabindented==-1) tabindented=0;
      }

      while(x[e+1..e+1]=="\t")
      {
	ret+=({
	  Sgml.Tag("ex_indent", ([]), pos+e),
	  Sgml.Tag("ex_indent", ([]), pos+e),
	  Sgml.Tag("ex_indent", ([]), pos+e),
	  Sgml.Tag("ex_indent", ([]), pos+e),
	    });
	e++;
      }

      while(x[e+1..e+2]=="  ")
      {
	ret+=({ Sgml.Tag("ex_indent", ([]), pos+e) });
	e+=2;
      }
      break;

    case '/':
      if(x[e+1..e+1]=="/")
      {
	p=e++;
	while(x[e]!='\n') e++;
	e--;
	ret+=({ Sgml.Tag("ex_comment",([]), pos+e, ({ x[p..e]}) ) }); 
	break;
      }
	
      if(x[e+1..e+1]=="*")
      {
	p=e++;
	while(x[e..e+1]!="*/") e++;
	e++;
	ret+=({ Sgml.Tag("ex_comment",([]), pos+e, ({ x[p..e]}) ) }); 
	break;
      }
      
    default:
      ret[-1]+=x[e..e];
      continue;
    }
    ret+=({ "" });
  }

  return Sgml.Tag("example",([]),pos,ret);
}

string classbase;

string name_to_link(string x)
{
  return replace(x,({"->","-&gt;"}),({".","."}));
}

SGML make_concrete_wmml(SGML data)
{
  if(!data) return 0;
  SGML ret=({});

  foreach(data, TAG tag)
  {
    if(stringp(tag))
    {
      ret+=({tag});
    }else{
      switch(tag->tag)
      {
	case "include":
	  ret+=make_concrete_wmml(Sgml.group(Sgml.lex(Stdio.read_file(tag->params->file),tag->params->file)));
	  continue;
	  
	case "chapter":
	case "preface":
	case "introduction":
	case "section":
	case "table":
	case "appendix":
	case "image":
	case "illustration":
	  if(tag->params->name)
	  {
	    TAG t=Sgml.Tag(tag->tag,
			   tag->params,
			   tag->pos,
			   tag->data=make_concrete_wmml(tag->data),
			   tag->file);
	    ret+=({
	      Sgml.Tag("anchor",
		       (["name":tag->params->name,"type":tag->tag]),
		       tag->pos,
		       ({
			 t
			   }))
		});
	    continue;
	  }
	  break;

	case "class":
	case "module":
	{
	  string tmp=classbase;
	  if(!classbase || classbase=="")
	  {
	    classbase=tag->params->name;
	  }else{
	    classbase+="."+tag->params->name;
	  }
	  ret+=({
	    Sgml.Tag("anchor",(["name":classbase,"type":tag->tag]),tag->pos,
		make_concrete_wmml(tag->data))
	  });
	  classbase=tmp;
	  continue;
	}

	case "man_syntax":
	case "man_example":
	case "man_nb":
	case "man_bugs":
	case "man_description":
	case "man_see":
	{
	  string title=tag->tag;
	  SGML args=tag->data;
	  sscanf(title,"man_%s",title);
	  switch(title)
	  {
	    case "nb": title="nota bene"; break;
	    case "syntax":
	    case "example":
	      args=({Sgml.Tag("tt",([]),tag->pos,tag->data)});
	      break;

	    case "see":
	    {
	      title="see also";
	      SGML tmp=({});
	      foreach(replace(Sgml.get_text(args),({" ","\n"}),({"",""}))/",",string name)
		{
		  tmp+=({
		    Sgml.Tag("link",(["to":name_to_link(name)]),tag->pos,
			     ({
			       Sgml.Tag("tt",([]),tag->pos,({name})),
				 })),
		      ", "
			});
		}
	      
	      tmp[-1]="";
	      if(sizeof(tmp)>3) tmp[-3]=" and ";
	      
	      args=tmp;
	      break;
	    }
	  }
	  title=upper_case(title);
	  ret+=make_concrete_wmml(
	    ({
	    Sgml.Tag("man_title",(["title":title]),tag->pos,args),
	      }));
	  continue;
	}

	case "method":
	case "function":
	{
	  string fullname;
	  switch(tag->tag)
	  {
	    case "method":
	      fullname=classbase+"->"+tag->params->name;
	      break;
	    case "function":
	      fullname=classbase+"."+tag->params->name;
	      break;
	  }
	  ret+=make_concrete_wmml(({
	    Sgml.Tag("anchor",(["name":name_to_link(fullname),
	    "type":"method",]),tag->pos,
		     ({
		       Sgml.Tag("dl",([]),tag->pos,
				  ({
				    Sgml.Tag("man_title",(["title":upper_case(tag->tag)]),tag->pos,
					     ({
					       Sgml.Tag("tt",([]),tag->pos,({fullname})),
						 " - ",
						   tag->params->title,
						   })
					     )
				  })
				  +
				  tag->data
			 )
		     })),
	      "\n",
	      Sgml.Tag("hr"),
	  }));
	  continue;
	}
	  
	case "example":
	  switch(tag->params->language)
	  {
	    case "pike":
	      ret+=({parse_pike_code(tag->data[0],
				     tag->pos,
				     reserved_pike)});
	      continue;
	      
	    case "c":
	      ret+=({parse_pike_code(tag->data[0],
				      tag->pos,
				      reserved_c)});
	      continue;
	  }
      }
      ret+=({Sgml.Tag(tag->tag,
		      tag->params,
		      tag->pos,
		      make_concrete_wmml(tag->data),
		      tag->file)});
    }
  }
  return ret;
}

void save_image_cache();

int gifnum;
mapping gifcache=([]);

string mkgif(object o)
{
  string g=o->togif();
  int key=hash(g);

  foreach(gifcache[key]||({}),string file)
    {
      if(Stdio.read_file(file)==g)
      {
	werror("Cache hit in mkgif: "+file+"\n");
	return file;
      }
    }

  gifnum++;
  string gifname="illustration"+gifnum+".gif";
  rm(gifname);
  werror("Writing "+gifname+".\n");
  Stdio.write_file(gifname,g);

  if(gifcache[key])
    gifcache[key]+=({gifname});
  else
    gifcache[key]=({gifname});

  return gifname;
}


object render_illustration(string pike_code, mapping params, float dpi)
{
  werror("Rendering ");
  string src=params->src;
  object img=Image.image();

  if(params->dpi) dpi=(float)params->dpi;
  if(params->scale) dpi/=(float)params->scale;
  float scale=75.0/dpi;

  if(params->src) img=img->fromppm(Process.popen("anytopnm 2>/dev/null "+src));
  if(scale!=1.0) img=img->scale(scale);
  return compile_string("object `()(object src){ "+pike_code+" ; }")()(img);
}

private static string mkkey(mapping params, mixed ... other)
{
  params+=([]);
  m_delete(params,"align");
  m_delete(params,"alt");
  if(params->src)
    if(mixed x=file_stat(params->src))
      params->mtime=(string)(x[3]);
  string *keys=indices(params);
  string *values=values(params);
  sort(keys,values);

  return encode_value( ({keys,values,other}) );
}

mapping illustration_cache=([]);
string illustration_to_gif(TAG data, float dpi)
{
  mapping params=data->params;
  string pike_code=data->data[0];
  string key=mkkey(params,pike_code,dpi);

  string ret=illustration_cache[key];
  if(!ret)
  {
    ret=mkgif(render_illustration(pike_code,params, dpi));
    illustration_cache[key]=ret;
    save_image_cache();
  }
  return ret;
}

string image_to_gif(TAG data, float dpi)
{
  mapping params=data->params;
  if(params->xfig)
    params->src=params->xfig+".fig";

  string key=mkkey(params,dpi);

  string ret=illustration_cache[key];
  if(!ret)
  {
    if(!params->src)
    {
      werror("Image without source near pos "+data->pos+".\n");
      return "";
    }
    string ext=reverse(params->src);
    sscanf(ext,"%s.",ext);
    switch(reverse(ext))
    {
    case "fig":
      werror("Converting ");
      Process.system("fig2dev -L ps "+params->src+" ___tmp.ps;echo showpage >>___tmp.ps");
      Process.system("gs -q -sDEVICE=pbmraw -r225 -g2500x2500 -sOutputFile=___tmp.ppm ___tmp.ps </dev/null >/dev/null");
      object o=Image.image()->fromppm(Stdio.read_file("___tmp.ppm"))->autocrop()->scale(1.0/3)->rotate(-90);
      o=Image.image(o->xsize()+40, o->ysize()+40, 255,255,255)->paste(o,20,20);
      rm("___tmp.ps");
      rm("___tmp.ppm");
      ret=mkgif(o);
      break;

    default:
      ret=mkgif(render_illustration("return src",params,dpi));
      break;
    }

    illustration_cache[key]=ret;
    save_image_cache();
  }
  return ret;
}

void save_image_cache()
{
  rm("illustration_cache");
  Stdio.write_file("illustration_cache",
		   encode_value(([
		     "gifnum":gifnum,
		     "gifcache":gifcache,
		     "illustration_cache":illustration_cache,
		     ])));
}

void create()
{
  if(file_stat("illustration_cache"))
  {
    mixed x=decode_value(Stdio.read_file("illustration_cache"));
    gifnum=x->gifnum;
    gifcache=x->gifcache;
    illustration_cache=x->illustration_cache;
  }
}

int chapters;
int appendices;

static private SGML low_collect_toc(mixed *data,
				    string prefix,
				    int *current)
{
  SGML ret=({});

  foreach(data, TAG t)
    {
      if(objectp(t))
      {
	switch(t->tag)
	{
	case "section":
	  t->params->number=prefix+(string)current[-1];
	  
	  ret+=({
	    Sgml.Tag("section_toc",
		     t->params,
		     t->pos,
		     low_collect_toc(t->data,
				 t->params->number+".",
				 current+({1})))
	      });	      ;
	  current[-1]++;
	  break;

	case "chapter":
	  if(current)
	    werror("Chapter inside chapter/appendix near "+t->pos+".\n");
	  t->params->number=(string)chapters;

	  ret+=({
	    Sgml.Tag("chapter_toc",
		     t->params,
		     t->pos,
		     low_collect_toc(t->data,
				 t->params->number+".",
				 ({1})))
	      });
	  chapters++;
	  break;
	  
	case "appendix":
	  if(current)
	    werror("Appendix inside chapter/appendix near "+t->pos+".\n");
	  
	  t->params->number=sprintf("%c",appendices);
	  
	  ret+=({
	    Sgml.Tag("appendix_toc",
		     t->params,
		     t->pos,
		     low_collect_toc(t->data,
				 t->params->number+".",
				 ({1}))),
	      });
	  appendices++;
	  break;

	case "preface":
	  if(current)
	    werror("Preface inside chapter/appendix near "+t->pos+".\n");

	  t->params->number="preface";
	  
	  ret+=({
	    Sgml.Tag("preface_toc",
		     t->params,
		     t->pos,
		     low_collect_toc(t->data,
				 t->params->number+".",
				 ({1}))),
	      });
	  break;

	case "introduction":
	  if(current)
	    werror("Introduction inside chapter/appendix near "+t->pos+".\n");

	  t->params->number="introduction";
	  
	  ret+=({
	    Sgml.Tag("introduction_toc",
		     t->params,
		     t->pos,
		     low_collect_toc(t->data,
				 t->params->number+".",
				 ({1}))),
	      });
	  break;

	case "index":
	case "table-of-contents":
	  t->params->number=t->tag;
	  ret+=({
	    Sgml.Tag(t->tag+"_toc",
		     t->params,
		     t->pos)
	      });
	  break;


	default:
	  if(t->data)
	    ret+=low_collect_toc(t->data,prefix,current);
	}
      }
    }
  return ret;
}

SGML sort_toc(SGML toc)
{
  // Assume correct order
  return toc;
}

SGML collect_toc(SGML data)
{
  SGML toc;
  chapters=1;
  appendices='A';
  toc=low_collect_toc(data,"",0);
  return sort_toc(toc);
}

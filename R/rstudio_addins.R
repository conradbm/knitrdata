# Functions meant to be used as Rstudio addins ---------------------------------------

isemp = function(x) is.null(x) || (x=="")

# Function for creating a data chunk --------------------

#' Invoke Shiny gadget to create a data chunk
#'
#' As different elements of the data chunk are specified, other options will be modified
#' as is likely to be useful. For example, if a binary file is uploaded, then the \code{format}
#' will be set to \code{binary}, the \code{encoding} will be set to \code{base64} and the
#' \code{Encode data?} option will be checked. If these options are not appropriate, then they can
#' be altered afterwards.
#'
#' When the \code{Create chunk} button is clicked, the function will return the chunk contents
#' including header and tail.
#'
#' @param title Text to place in title bar of gadget.
#' @param infobar Text to place in information bar at top of gadget
#'
#' @return Invisibly returns the text of the data chunk as a character vector, one line per element.
#'
#' @examples
#' \dontrun{
#' create_data_chunk_dialog()
#' }
#'
#' @export
#'
#' @family Chunk tools
#' @author David M. Kaplan \email{dmkaplan2000@@gmail.com}
#' @encoding UTF-8
create_data_chunk_dialog = function (title="Data chunk creator",
                                     infobar="Fill out  click above to create chunk") {
  if (!requireNamespace("shiny",quietly=TRUE) || !requireNamespace("miniUI",quietly=TRUE))
    stop("This function requires that the shiny and miniUI packages be installed. Please install them before running.")

  ui <- miniUI::miniPage(
    miniUI::gadgetTitleBar(title,left = miniUI::miniTitleBarCancelButton(),
                   right = miniUI::miniTitleBarButton("done", "Create chunk", primary = TRUE)),
    miniUI::miniContentPanel(
      shiny::h3(shiny::textOutput('infobar')),
      shiny::hr(),
      shiny::fileInput("filename","Data file: "),
      shiny::textInput("chunk_label","Chunk label: ",placeholder="mydatachunk",width="100%"),
      shiny::fillRow(
        height="40pt",
        shiny::checkboxGroupInput("format","Format: ",choices=c("text","binary"),selected="binary",inline=TRUE),
        shiny::checkboxGroupInput("encoding","Encoding: ",choices=c("asis","base64"),select="base64",inline=TRUE)
      ),
      shiny::fillRow(
        height="40pt",
        shiny::checkboxInput("md5sum","Do MD5 sum check? ",value=TRUE),
        shiny::checkboxInput("encode","Encode the data? ",value=TRUE)
      ),
      shiny::textInput("output.var","Output variable name (no quotes): ",placeholder="df",width="100%"),
      shiny::textInput("output.file","Output file name (no quotes): ",placeholder="filepath/filename.ext",
                width="100%"),
      shiny::textInput("loader.function","Loader function: ",placeholder="read.csv",width="100%"),
      shiny::textInput("eval","Evaluate chunk? ",value="TRUE",width="100%"),
      shiny::checkboxInput("echo","Echo chunk contents? ",value=FALSE),
      shiny::textInput("chunk_options_string","Additional chunk options (as they would appear in chunk header): ",
                placeholder="loader.ops=list(header=FALSE), max.echo=5",width="100%")
    )
  )

  server <- function(input, output, session) {
    rv = shiny::reactiveValues(makechunk=FALSE)

    output$infobar = shiny::renderText(infobar)

    # When data file set, determine defaults
    shiny::observeEvent(input$filename,{
      fn = input$filename$datapath

      isbin = is.file.binary(fn)
      fnext = tolower(tools::file_ext(fn))

      shiny::updateCheckboxGroupInput(session,"format",selected=ifelse(isbin,"binary","text"))
      shiny::updateCheckboxGroupInput(session,"encoding",selected=ifelse(isbin,"base64","asis"))
      shiny::updateCheckboxInput(session,"encode",value=isbin)
      shiny::updateTextInput(session,"loader.function",
                      placeholder=ifelse(isbin,"readRDS","read.csv"))

      # Try to guess loader.function
      lfs = c(csv="read.csv",rds="readRDS")
      if (fnext %in% names(lfs))
        shiny::updateTextInput(session,"loader.function",
                               value=as.character(lfs[fnext]))
    })

    shiny::observeEvent(input$output.file,{
      if (!isemp(input$output.file)) {
        shiny::updateTextInput(
          session,"eval",
          value=paste0("!file.exists(\"",as.character(input$output.file),"\")")
        )
      }
    })

    # When the "create chunk" button is clicked, return a value
    shiny::observeEvent(input$done, {
      makechunk = TRUE

      fn = input$filename$datapath
      if (is.null(fn)) {
        makechunk = FALSE
        shiny::showModal(shiny::modalDialog("Data file must be specified."))
      }

      if (isemp(input$output.var) && isemp(input$output.file)) {
        makechunk = FALSE
        shiny::showModal(shiny::modalDialog("At least one of output variable or output file must be given."))
      }

      if (isemp(input$output.var) && !isemp(input$loader.function)) {
        makechunk = FALSE
        shiny::showModal(shiny::modalDialog("Loader function only has value if output variable name specified."))
      }

      rv$makechunk = makechunk
    })

    shiny::observeEvent(rv$makechunk, {
      if (rv$makechunk) {
        fn = input$filename$datapath

        md5sum = NULL
        if (input$md5sum)
          md5sum = tools::md5sum(fn)
        names(md5sum) = NULL

        # Read and encode data
        if (input$encode && input$encoding != 'asis') {
          chunk = data_encode(fn,encoding = input$encoding)
        } else {
          chunk = readLines(fn)
        }

        chunk = do.call(c,strsplit(chunk,"\n")) # Break into lines
        chunk_label = NULL
        if (!isemp(input$chunk_label))
          chunk_label = input$chunk_label

        args = list(text=chunk,
                    chunk_label=chunk_label,
                    format=input$format,encoding=input$encoding)

        if (!isemp(input$output.var))
          args$output.var=input$output.var
        if (!isemp(input$output.file))
          args$output.file=input$output.file

        args$echo=input$echo

        if (!isemp(md5sum))
          args$md5sum = md5sum

        # Things going in extra args
        ev = NULL
        if (!isemp(input$eval))
          ev=paste0("eval=",input$eval)

        lf = NULL
        if (!isemp(input$loader.function))
          lf=paste0("loader.function=",input$loader.function)

        co = NULL
        if (!isemp(input$chunk_options_string))
          co = input$chunk_options_string

        co=paste(c(ev,lf,co),collapse=",")

        if (!isemp(co))
          args$chunk_options_string = co

        chunk = do.call(create_chunk,args)

        shiny::stopApp(chunk)
      }
    })

    # When the cancel button is clicked, return null
    shiny::observeEvent(input$cancel, {
      shiny::stopApp(NULL)
    })
  }

  chunk = shiny::runGadget(
    app=ui, server=server,
    viewer = shiny::dialogViewer(title))

  invisible(chunk)
}

# Insert data chunk ------------------------------
#' Invoke Rstudio addin to insert a data chunk in active source document
#'
#' As different elements of the data chunk are specified, other options will be modified
#' as is likely to be useful. For example, if a binary file is uploaded, then the \code{format}
#' will be set to \code{binary}, the \code{encoding} will be set to \code{base64} and the
#' \code{Encode data?} option will be checked. If these options are not appropriate, then they can
#' be altered afterwards.
#'
#' When the \code{Create chunk} button is clicked, the contents of the data chunk will be inserted
#' at the current cursor location of the active source document in the Rstudio editor.
#'
#' @param title Text to place in title bar of gadget.
#' @param chunk Text content of the data chunk. If not given (as is typically the case), the
#'   \code{\link{create_data_chunk_dialog}} will be used to generate chunk contents.
#'
#' @return Returns \code{TRUE} if a chunk was inserted, \code{FALSE} otherwise.
#'
#' @examples
#' \dontrun{
#' insert_data_chunk_dialog()
#' }
#'
#' @export
#'
#' @family Chunk tools
#' @author David M. Kaplan \email{dmkaplan2000@@gmail.com}
#' @encoding UTF-8
insert_data_chunk_dialog = function (title="Data chunk inserter",
                                     chunk = NULL) {
  if (!requireNamespace("rstudioapi",quietly=TRUE))
    stop("The rstudioapi package must be installed to use this function.")

  context = rstudioapi::getSourceEditorContext()
  infobar = paste0("Active document: ",ifelse(isemp(context$path),"<<UNKNOWN>>",context$path))

  chunk = create_data_chunk_dialog(title=title,infobar=infobar)

  if (is.null(chunk))
    invisible(FALSE)

  ln = as.integer(context$selection[[1]]$range$start["row"])

  txt = insert_chunk(
    chunk = chunk,
    line = ln,
    rmd.text = context$contents
  )

  rstudioapi::setDocumentContents(paste(txt,collapse="\n"),context$id)

  cat("line ",ln,"\n")

  # Set position - causes errors for some unknown reason
  rstudioapi::setCursorPosition(
    rstudioapi::document_position(ln,1),
    context$id)

  cat("line ",ln,"\n")

  return("test")
}

# Remove chunks ------------------------------

#' Invoke Rstudio addin to remove chunks from the active source document
#'
#' The dialog will present a data table list of chunks in the source document. Select the rows
#' that correspond to the chunks that you wish to remove and hit the \code{Remove chunks} button
#' to remove them.
#'
#' When the dialog is started, if the cursor is positioned inside a chunk in the source document,
#' then the row corresponding to this chunk will be selected by default.
#'
#' @param title Text to place in title bar of gadget.
#'
#' @return Returns \code{TRUE} if one or more chunks were removed, \code{FALSE} otherwise.
#'
#' @examples
#' \dontrun{
#' remove_chunks_dialog()
#' }
#'
#' @export
#'
#' @family Chunk tools
#' @author David M. Kaplan \email{dmkaplan2000@@gmail.com}
#' @encoding UTF-8
remove_chunks_dialog = function (title="Eliminate (data) chunks") {
  if (!requireNamespace("shiny",quietly=TRUE) || !requireNamespace("miniUI",quietly=TRUE) ||
      !requireNamespace("DT",quietly=TRUE) || !requireNamespace("rstudioapi",quietly=TRUE))
    stop("This function requires that the shiny, miniUI, DT and rstudioapi packages be installed. Please install them before running.")

  ui <- miniUI::miniPage(
    miniUI::gadgetTitleBar(title,left = miniUI::miniTitleBarCancelButton(),
                           right = miniUI::miniTitleBarButton("done", "Remove chunks", primary = TRUE)),
    miniUI::miniContentPanel(
      shiny::h3(shiny::textOutput('actdoc')),
      shiny::hr(),
      DT::dataTableOutput('chunklist')
    )
  )

  server <- function(input, output, session) {
    context = rstudioapi::getSourceEditorContext()

    output$actdoc = shiny::renderText(paste0("Active document: ",context$path))

    chunks = list_rmd_chunks(context$contents)
    rv = shiny::reactiveValues(chunks = chunks)

    # See if highlighted area touches any chunks
    se = c(context$selection[[1]]$range$start["row"],
           context$selection[[1]]$range$end["row"])

    row = which(chunks$start <= se[2] & se[1] <= chunks$end)

    if (length(row) > 0) {
      proxy = DT::dataTableProxy("chunklist",session)
      DT::selectRows(proxy,selected=row)
    }

    # render data table when list of chunks changed
    shiny::observeEvent(rv$chunks,{
      output$chunklist = DT::renderDataTable(rv$chunks,server=FALSE)
    })

    shiny::observeEvent(input$done, {
      rows = input$chunklist_rows_selected

      if(is.null(rows) || length(rows)==0)
        shiny::stopApp(FALSE)

      contents = context$contents
      chunks = rv$chunks[rows,]

      # Get full list of line numbers to remove
      se = as.data.frame(t(chunks[,c("start","end"),drop=FALSE]))
      lns = do.call(c,lapply(se,function(x) x[1]:x[2]))

      # Remove rows
      contents = contents[-1*lns]

      # Put into document
      rstudioapi::setDocumentContents(paste(contents,collapse="\n"),context$id)
      rstudioapi::setCursorPosition(
        rstudioapi::document_position(min(lns)-1,1),
        context$id)

      shiny::stopApp(TRUE)
    })

    # When the cancel button is clicked, return null
    shiny::observeEvent(input$cancel, {
      shiny::stopApp(FALSE)
    })
  }

  res = shiny::runGadget(
    app=ui, server=server,
    viewer = shiny::dialogViewer(title))

  invisible(res)
}
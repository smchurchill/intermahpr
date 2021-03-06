## intermahp - International Model of Alcohol Harms and Policies
## Copyright (C) 2018 Canadian Institute for Substance Use Research

# --- datasets server --- #

# only enable the upload buttons when their corresponding input has a file selected ----
# Adapted from the ddPCR R package written by Dean Attali
observeEvent(
  {
    input$upload_rr
    input$upload_pc
    input$upload_dh
  },
  ignoreNULL = FALSE,
  {
    toggleState(
      "upload_files_btn",
      !is.null(input$upload_pc) && !is.null(input$upload_rr) && !is.null(input$upload_dh)
    )
  }
)

# New data upload button ----
observeEvent(input$datasets_new_upload_btn, {
  withBusyIndicator("datasets_new_upload_btn", {
    pc <- readr::read_csv(input$datasets_upload_pc$datapath)
    rr <- readr::read_csv(input$datasets_upload_rr$datapath)
    mm <- readr::read_csv(input$datasets_upload_mm$datapath)
    
    ## Morbidity/Mortality not strictly necessary data.  If there are no observations, make a dummy table.
    if(nrow(mm) == 0) mm <- tibble::tibble(
      region = "None", 
      year = 0,
      gender = "Male",
      age_group = "None",
      im = "(0).(0)",
      outcome = "None", 
      count = 0
    )
    
    ## We want descriptive, helpful error messages when the input data is malformed.
    
    
    ## First, check all datasets for missing vars
    pc_missingvars_flag <- FALSE
    clean_pc <- tryCatch(
      {
        clean(pc, intermahpr::getExpectedVars("pc"))
      },
      error = function(e) {
        pc_missingvars_flag <<- TRUE
        gsub("A supplied", "Prevalence and consumption", e$message)
      }
    )

    rr_missingvars_flag <- FALSE
    clean_rr <- tryCatch(
      {
        clean(rr, intermahpr::getExpectedVars("rr"))
      },
      error = function(e) {
        rr_missingvars_flag <<- TRUE
        e$message
        gsub("A supplied", "Relative risk", e$message)
      }
    )
    
    mm_missingvars_flag <- FALSE
    clean_mm <- tryCatch(
      {
        clean(mm, intermahpr::getExpectedVars("mm"))
      },
      error = function(e) {
        mm_missingvars_flag <<- TRUE
        gsub("A supplied", "Morbidity and mortality", e$message)
      }
    )
    
    ## If any table has missing vars, the associcated error message is stored in
    ## the variable clean_XX and its corresp flag is set to true.
    missingvars_flags <- c(pc_missingvars_flag, rr_missingvars_flag, mm_missingvars_flag)
    
    if(sum(missingvars_flags)) {
      stop(
        c(
          "\n",
          if(pc_missingvars_flag) clean_pc else "",
          if(rr_missingvars_flag) clean_rr else "",
          if(mm_missingvars_flag) clean_mm else ""
        )
      )
    }
    
    ## Otherwise, the clean_XX vars are datatables, and we can continue.
    prep_rr <- prepareRR(clean_rr, ext = T)
    
    # Ensure data cohesion (currently tests: gender levels match)
    # 
    stop_message <- ""
    
    g_flag <- !(prod(clean_pc$gender %in% prep_rr$gender) && prod(clean_mm$gender %in% prep_rr$gender))
    
    if(g_flag) {
      stop_message <- paste(
        stop_message,
        "Gender levels are not consistent between uploaded datasets."
      )
    }
    
    # If any cohesion flag is raised, send an error
    flags <- c(g_flag)
    if(sum(flags)) stop(stop_message)
    
    # Set variables
    dataValues$genders <- unique(as.character(prep_rr$gender))
    
    dataValues$pc_raw <- pc
    dataValues$pc_in <- clean_pc
    
    dataValues$rr_raw <- rr
    dataValues$rr_in <- clean_rr
    
    dataValues$mm_raw <- mm
    dataValues$mm_in <- clean_mm
    
    output$dataChosen <- reactive({ TRUE })
    
    shinyjs::enable("nav_settings")
    shinyjs::enable("nav_generate_estimates")
    shinyjs::enable("generate_estimates")
  })
})


# Saved data upload button ----
observeEvent(input$datasets_saved_upload_btn, {
  withBusyIndicator("datasets_saved_upload_btn", {
    showNotification("Not Implemented Yet")
  })
})

# Sample data load ----
# * Select sample datasets render ----
output$datasets_sample_years_render <- renderUI({
  pickerInput(
    inputId = "datasets_sample_years",
    label = "Years of study",
    choices = unique(preloaded_dataset_pc$year),
    selected = unique(preloaded_dataset_pc$year)[1],
    multiple = T,
    options = list(
      `actions-box` = TRUE, 
      `selected-text-format` = "count > 2",
      `count-selected-text` = paste("{0}/{1}", "years")
    )
  )  
})


observe({
  if(
    (length(input$datasets_sample_years) > 0)
  ) {
    enable(id = "datasets_sample_load_btn")
  } else{
    disable(id = "datasets_sample_load_btn")
  }
})

#* Update samples when not visible
outputOptions(output, "datasets_sample_years_render", suspendWhenHidden = FALSE)


# * Button ----
observeEvent(input$datasets_sample_load_btn, {
  withBusyIndicator("datasets_sample_load_btn", {
    
    if(input$datasets_sample_rr == "Zhao") dataValues$rr_in <- preloaded_dataset_rr_zhao
    if(input$datasets_sample_rr == "Roerecke") dataValues$rr_in <- preloaded_dataset_rr_roerecke
    
    dataValues$pc_in <- dplyr::filter(
      preloaded_dataset_pc,
      year %in% input$datasets_sample_years 
    )
    
    dataValues$mm_in <- dplyr::filter(
      preloaded_dataset_mm, 
      year %in% input$datasets_sample_years 
    )
    
    dataValues$rr_raw <- dataValues$rr_in
    dataValues$pc_raw <- dataValues$pc_in
    dataValues$mm_raw <- dataValues$mm_in
    
    # Set variables
    dataValues$genders <- c("Male", "Female")
    
    show("datasets_nextMsg")
    
    output$dataChosen <- reactive({ TRUE })
  })
})

# Metadata for loaded datasets ----
#* 

output$pc_metadata <- renderUI({
  pc <- dataValues$pc_in
  if(is.null(pc)) return("")
  
  obs <- nrow(pc)
  years <- length(unique(pc$year))
  regions <- length(unique(pc$region))
  cohorts <- length(unique(pc$gender)) * length(unique(pc$age_group))
  
  div(
    class = "data-info",
    paste0("Prevalence and consumption:"),
    div(
      class = "padded-data-info",
      paste0(
        obs,
        " observation", if(obs >= 2) "s",
        " over ",
        years,
        " year", if(years >= 2) "s",
        ", ",
        regions,
        " region", if(regions >= 2) "s",
        " and ",
        cohorts,
        " gender-age group", if(cohorts >= 2) "s",
        "."
      )
    )
  )
})

output$rr_metadata <- renderUI({
  rr <- dataValues$rr_in
  if(is.null(rr)) return("")
  
  obs <- nrow(rr)
  conditions <- length(unique(rr$im))

  div(
    class = "data-info",
    paste0("Relative risks:"),
    div(
      class = "padded-data-info",
      paste0(
        obs,
        " function specification", if(obs >= 2) "s",
        " across ",
        conditions,
        " condition", if(conditions >= 2) "s",
        "."
      )
    )
  )
})


output$mm_metadata <- renderUI({
  mm <- dataValues$mm_in
  if(is.null(mm)) return("")
  
  years <- length(unique(mm$year))
  regions <- length(unique(mm$region))
  cohorts <- length(unique(mm$gender)) * length(unique(mm$age_group))
  conditions <- length(unique(mm$im))
  morbidities <- nrow(filter(mm, grepl("Morb", outcome)))
  mortalities <- nrow(filter(mm, grepl("Mort", outcome)))
    
  div(
    class = "data-info",
    paste0("Morbidity and mortality:"),
    div(
      class = "padded-data-info",
      paste0(
        morbidities,
        " morbidity and ",
        mortalities,
        " mortality counts over ",
        years,
        " year", if(years >= 2) "s",
        ", ",
        regions,
        " region", if(regions >= 2) "s",
        " and ",
        cohorts,
        " gender-age group", if(cohorts >= 2) "s",
        " across ",
        conditions,
        " condition", if(conditions >= 2) "s",
        "."
      )
    )
  )
})

current_loaded_data <- reactive({
  dataValues[[paste0(input$loaded_raw_data, "_raw")]]
})

datasets_summary_dt <- reactive({
  DT::datatable(
    rownames = FALSE,
    data = current_loaded_data(),
    filter = "top",
    extensions = "Buttons",
    options = base_options
  )
})

output$datasets_summary_dt_render <- DT::renderDataTable(datasets_summary_dt())

# nextMsg links ----
observeEvent(input$datasets_to_settings, set_nav("settings"))
observeEvent(input$datasets_to_generate_estimates, set_nav("generate_estimates"))

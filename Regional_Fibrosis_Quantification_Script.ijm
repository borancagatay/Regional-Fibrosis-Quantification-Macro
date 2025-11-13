
var inputDir = "";
var outputDir = "";
var roiNames = newArray("LA", "RA", "LV-Base", "LV-Mid", "IVS-base", "IVS-Mid", "Global LV", "RV-base", "RV-mid", "Apex", "Perivascular fibrosis");
var currentImageID = 0;
var originalImageID = 0;
var workingImageID = 0;
var binaryImageID = 0;
var filename = "";
var divisionLinesOverlay = 0; // To store overlay ID for division lines

// Main function
function main() {
    inputDir = getDirectory("Choose input folder with heart images");
    outputDir = getDirectory("Choose output folder for results");

    File.makeDirectory(outputDir + "ROI_Images" + File.separator);
    File.makeDirectory(outputDir + "Binary_Images" + File.separator);
    File.makeDirectory(outputDir + "Fibrosis_Images" + File.separator);

    fileList = getFileList(inputDir);
    imageFiles = getImageFiles(fileList);

    if (imageFiles.length == 0) {
        showMessage("No image files found!");
        return;
    }

    initializeResultsTables();

    for (i = 0; i < imageFiles.length; i++) {
        print("\\Clear");
        print("Processing image " + (i+1) + " of " + imageFiles.length + ": " + imageFiles[i]);

        // Set the global filename variable here
        filename = imageFiles[i];

        processImage(imageFiles[i]);
        saveResults();
        cleanupWindows();
    }

    showMessage("Analysis complete! Check output folder for results.");
}

function processImage(filename) {
    open(inputDir + filename);
    originalImageID = getImageID();
    run("Duplicate...", "title=Working_" + filename);
    workingImageID = getImageID();

    selectIndividualRegions(filename);
    excludeArtifacts(filename);

    currentImageID = workingImageID;
    print("Original Image ID: " + originalImageID);
    print("Working Image ID: " + workingImageID);
    
    measureTissuePercentages(filename);
    measureFibrosisPercentages(filename);
    saveProcessedImages(filename);
}

function selectIndividualRegions(filename) {
    // Switch to original color image for ROI drawing
    selectImage(originalImageID);
    
    // Clear ROI Manager
    if (isOpen("ROI Manager")) {
        selectWindow("ROI Manager");
        run("Close");
    }
    run("ROI Manager...");
    
    // Step 7: Select individual parts on original color image with yes/no questions
    var laRaSelected = false;
    var divisionLinesCreated = false;
    
    for (i = 0; i < roiNames.length; i++) {
        selectImage(originalImageID); // Ensure we're on the original color image
        
        // Step 8: Yes/No question for each region
        Dialog.create("Region Present: " + roiNames[i]);
        Dialog.addMessage("Is the " + roiNames[i] + " present in this image?");
        Dialog.addChoice("Response:", newArray("Yes", "No"), "Yes");
        Dialog.show();
        
        response = Dialog.getChoice();
        
        if (response == "Yes") {
            // Create division lines before the first ROI selection
            if (!divisionLinesCreated) {
                createBaseMidApexDivision();
                divisionLinesCreated = true;
            }
            
            // Make sure we're viewing the original color image
            selectImage(originalImageID);
            setTool("polygon");
            
            // Special handling for Perivascular fibrosis (multiple selections allowed)
            if (roiNames[i] == "Perivascular fibrosis") {
                var perivasularCount = 0;
                var continuePerivascular = true;
                
                while (continuePerivascular) {
                    waitForUser("Select Perivascular Fibrosis Area #" + (perivasularCount + 1), 
                        "Draw polygon around a PERIVASCULAR FIBROSIS area on the ORIGINAL COLOR IMAGE.\n" +
                        "You can select multiple separate perivascular areas.\n" +
                        "Outline each perivascular fibrosis region individually.\n" +
                        "Click OK when this selection is complete.");
                    
                    if (selectionType() != -1) {
                        roiManager("Add");
                        roiManager("Select", roiManager("count")-1);
                        perivasularCount++;
                        roiManager("Rename", "Perivascular_" + perivasularCount);
                        print("Added Perivascular ROI #" + perivasularCount);
                        run("Select None");
                        
                        // Ask if user wants to add more perivascular areas
                        Dialog.create("Add More Perivascular Areas?");
                        Dialog.addMessage("Do you want to select another perivascular fibrosis area?");
                        Dialog.addChoice("Response:", newArray("Yes", "No"), "No");
                        Dialog.show();
                        
                        continueResponse = Dialog.getChoice();
                        continuePerivascular = (continueResponse == "Yes");
                    } else {
                        print("No selection made for perivascular area - stopping");
                        continuePerivascular = false;
                    }
                }
                
                if (perivasularCount == 0) {
                    print("No perivascular areas selected");
                }
            } else {
                // Normal single ROI selection for other regions
                waitForUser("Select " + roiNames[i] + " on Original Color Image", 
                    "Draw polygon around " + roiNames[i] + " region on the ORIGINAL COLOR IMAGE.\n" +
                    "Outline the tissue boundaries of this region.\n" +
                    "Click OK when selection is complete.");
                
                if (selectionType() != -1) {
                    roiManager("Add");
                    roiManager("Select", roiManager("count")-1);
                    roiManager("Rename", roiNames[i]);
                    print("Added ROI: " + roiNames[i]);
                } else {
                    print("No selection made for " + roiNames[i] + " - skipping");
                }
            }
        } else {
            print("Skipped " + roiNames[i] + " - not present in image");
        }
    }
    
    run("Select None");
    print("Created " + roiManager("count") + " ROIs");
}

function createBaseMidApexDivision() {
    selectImage(originalImageID);
    
    // Clear any existing overlay
    run("Remove Overlay");
    
    showMessage("Base-Mid-Apex Division", 
        "Now you will draw a VERTICAL line to define the base-mid-apex division.\n\n" +
        "Instructions:\n" +
        "1. Draw a vertical line from top to bottom of the heart\n" +
        "2. This line will be divided into 3 equal parts (base, mid, apex)\n" +
        "3. Two perpendicular lines will be drawn automatically\n" +
        "4. These reference lines will help you select base/mid/apex ROIs\n\n" +
        "Click OK to start drawing the vertical line.");
    
    // Set line tool for drawing the vertical reference line
    setTool("line");
    
    waitForUser("Draw Vertical Division Line", 
        "Draw a VERTICAL line from top to bottom to define the heart axis.\n" +
        "This line will be used to create base-mid-apex divisions.\n" +
        "Click OK when the line is drawn.");
    
    // Get the coordinates of the drawn line
    if (selectionType() == 5) { // Line selection
        getSelectionCoordinates(xCoords, yCoords);
        
        if (xCoords.length >= 2) {
            // Calculate the division points (1/3 and 2/3 along the line)
            x1 = xCoords[0];
            y1 = yCoords[0];
            x2 = xCoords[1];
            y2 = yCoords[1];
            
            // Calculate 1/3 and 2/3 points along the line
            dx = x2 - x1;
            dy = y2 - y1;
            
            // First division point (1/3)
            x_div1 = x1 + dx/3;
            y_div1 = y1 + dy/3;
            
            // Second division point (2/3)
            x_div2 = x1 + 2*dx/3;
            y_div2 = y1 + 2*dy/3;
            
            // Calculate perpendicular direction (rotate 90 degrees)
            // For a line from (x1,y1) to (x2,y2), perpendicular is (-dy, dx)
            perp_dx = -dy;
            perp_dy = dx;
            
            // Normalize the perpendicular vector and scale it
            length = sqrt(perp_dx*perp_dx + perp_dy*perp_dy);
            if (length > 0) {
                perp_dx = perp_dx / length * 50000; 
                perp_dy = perp_dy / length * 50000;
            }
            
            // Create overlay for the division lines
            run("Remove Overlay");
            
            // Add the original vertical line to overlay
            makeSelection("line", newArray(x1, x2), newArray(y1, y2));
            run("Add Selection...", "stroke=red width=12");
            
            // Add first perpendicular line (base-mid division)
            x_start1 = x_div1 - perp_dx/2;
            y_start1 = y_div1 - perp_dy/2;
            x_end1 = x_div1 + perp_dx/2;
            y_end1 = y_div1 + perp_dy/2;
            
            makeSelection("line", newArray(x_start1, x_end1), newArray(y_start1, y_end1));
            run("Add Selection...", "stroke=blue width=15");
            
            // Add second perpendicular line (mid-apex division)
            x_start2 = x_div2 - perp_dx/2;
            y_start2 = y_div2 - perp_dy/2;
            x_end2 = x_div2 + perp_dx/2;
            y_end2 = y_div2 + perp_dy/2;
            
            makeSelection("line", newArray(x_start2, x_end2), newArray(y_start2, y_end2));
            run("Add Selection...", "stroke=blue width=15");
            
            // No need for additional point labels - the lines are sufficient
            
            run("Select None");
            
            showMessage("Division Lines Created", 
                "Base-Mid-Apex division lines have been created:\n\n" +
                "- Red line: Your original vertical reference\n" +
                "- Blue lines: Base-Mid and Mid-Apex divisions\n\n" +
                "These lines will remain visible during ROI selection\n" +
                "to help you identify base, mid, and apex regions.\n\n" +
                "Click OK to continue with ROI selection.");
        }
    } else {
        showMessage("No Line Drawn", "No line was drawn. Continuing without base-mid-apex division.");
    }
    
    run("Select None");
}

function excludeArtifacts(filename) {
    // Step 9: Exclude artifacts from Working image
    selectImage(workingImageID);
    
    Dialog.create("Artifact Removal");
    Dialog.addMessage("Remove artifacts from the Working image?");
    Dialog.addChoice("Response:", newArray("Yes", "No"), "Yes");
    Dialog.show();
    
    response = Dialog.getChoice();
    
    if (response == "Yes") {
        setTool("polygon");
        setBackgroundColor(255, 255, 255); // white
        
        continueRemoving = true;
        while (continueRemoving) {
            selectImage(workingImageID); // Work on Working image
            waitForUser("Remove Artifacts from Working Image", 
                "Select artifacts to remove and press Delete.\n" +
                "Selected areas will turn white (excluded from analysis).\n" +
                "This removes non-tissue artifacts from the Working image.\n" +
                "Click OK when finished with this round.");
            
            Dialog.create("Continue Artifact Removal?");
            Dialog.addMessage("Remove more artifacts?");
            Dialog.addChoice("Response:", newArray("Yes", "No"), "No");
            Dialog.show();
            
            continueResponse = Dialog.getChoice();
            continueRemoving = (continueResponse == "Yes");
        }
    }
    run("Select None");
}

function measureTissuePercentages(filename) {
    // Remove division lines overlay before starting measurements
    selectImage(originalImageID);
    run("Remove Overlay");
    
    if (roiManager("count") == 0) {
        print("No ROIs defined - skipping tissue measurement");
        return;
    }
    
    // Verify the working image exists
    if (!isOpen(workingImageID)) {
        print("ERROR: Working image with ID " + workingImageID + " is not open");
        return;
    }
    
    // Create binary image from working image
    selectImage(workingImageID);
    workingTitle = getTitle();
    print("Creating binary image from: " + workingTitle);
    run("Duplicate...", "title=Binary_" + filename);
    binaryImageID = getImageID();
    binaryTitle = getTitle();
    
    selectImage(binaryImageID);
    run("8-bit");
    setThreshold(1, 151); // Fixed: threshold bright pixels (tissue)
    setOption("BlackBackground", false);
    run("Convert to Mask");
    
    // Clear and Set measurements
    run("Set Measurements...", "redirect=None decimal=3");
    run("Set Measurements...", "area area_fraction min max redirect=None decimal=3");
    
    print("Created binary image: " + binaryTitle + " (ID: " + binaryImageID + ")");
    
    // Perform measurements on each ROI
    for (i = 0; i < roiManager("count"); i++) {
        // Always select binary image before each measurement
        selectImage(binaryImageID);
        
        // Select ROI and measure
        roiManager("Select", i);
        roiName = call("ij.plugin.frame.RoiManager.getName", i);
        
        run("Measure");
        
        // Get results
        roiArea = getResult("Area", nResults-1);
        tissueAreaFraction = getResult("%Area", nResults-1);

        // Calculate absolute tissue area from the area fraction
        tissueArea = (tissueAreaFraction / 100) * roiArea;
        
        // Store results in table
        row = Table.size("Tissue_Results");
        Table.set("Image", row, filename, "Tissue_Results");
        Table.set("ROI", row, roiName, "Tissue_Results");
        Table.set("Area_ROI", row, roiArea, "Tissue_Results");
        Table.set("Area_Tissue", row, tissueArea, "Tissue_Results");
        Table.set("%_Tissue", row, tissueAreaFraction, "Tissue_Results");
        Table.set("Threshold_Min", row, 1, "Tissue_Results");
        Table.set("Threshold_Max", row, 151, "Tissue_Results");
        Table.update("Tissue_Results");
        
        print("Tissue measurement for " + roiName + ": " + tissueAreaFraction + "%");
    }

    // Clean up
    run("Clear Results");
    run("Select None");
    
    print("Tissue measurements completed for " + filename);
}

function measureFibrosisPercentages(filename) {
    if (roiManager("count") == 0) {
        print("No ROIs defined - skipping fibrosis measurement");
        return;
    }
    
    // Create ONE fibrosis binary image for the entire image
    selectImage(workingImageID);
    run("Duplicate...", "title=Fibrosis_" + filename);
    fibrosisImageID = getImageID();
    
    // Perform color thresholding ONCE for the entire image
    run("Color Threshold...");
    waitForUser("Fibrosis Color Threshold - " + filename,
        "INSTRUCTIONS:\n" +
        "1. Use Threshold method: Default, Threshold Color: Red, color space: LAB, Dark mode: unselected\n" +
        "2. Use the original image for visual guidance.\n" +
        "3. Adjust thresholds to highlight ALL fibrotic areas in the image\n" +
        "4. When satisfied with threshold, click 'Select' to create selection.\n" +
        "5. Verify selection covers fibrotic areas\n" +
        "6. Click OK to continue\n\n" +
        "This threshold will be applied to ALL ROIs in: " + filename);
    
    // Close threshold window
    if (isOpen("Color Threshold")) {
        selectWindow("Color Threshold");
        run("Close");
    }
    
    // Create binary image using Make Binary
    selectImage(fibrosisImageID);
    
    if (selectionType() != -1) {
        // Use Make Binary to create the fibrosis mask
        run("Make Binary");
        rename("Fibrosis_" + filename + "_Binary");
        print("Created binary fibrosis image for " + filename + ": " + getTitle());
    } else {
        // No selection - create empty binary image
        run("8-bit");
        run("Select All");
        setForegroundColor(0, 0, 0); // Black
        run("Fill", "slice");
        run("Select None");
        rename("Fibrosis_" + filename + "_Binary");
        print("No fibrosis detected in " + filename + " - created empty binary");
    }
    
    fibrosisROI_ID = getImageID();
    
    // Set measurements
    run("Set Measurements...", "area mean area_fraction min max redirect=None decimal=3");
    
    // Now measure each ROI on the SAME binary fibrosis image
    for (i = 0; i < roiManager("count"); i++) {
        roiName = call("ij.plugin.frame.RoiManager.getName", i);
        print("Processing fibrosis for: " + roiName);
        
        // Measure on the single binary fibrosis image within each ROI
        selectImage(fibrosisROI_ID);
        roiManager("Select", i);
        run("Measure");
        
        // Get measurements
        roiArea = getResult("Area", nResults-1);  // This is the ROI area
        fibrosisAreaFraction = getResult("%Area", nResults-1);  // This is % fibrosis
        
        // Get tissue data from previous analysis
        tissueArea = Table.get("Area_Tissue", i, "Tissue_Results");
        tissueAreaFraction = Table.get("%_Tissue", i, "Tissue_Results");
        minThreshold = Table.get("Threshold_Min", i, "Tissue_Results");
        maxThreshold = Table.get("Threshold_Max", i, "Tissue_Results");

        // Calculate absolute fibrosis area from the area fraction
        fibrosisArea = (fibrosisAreaFraction / 100) * roiArea;
        
        // Calculate final fibrosis percentage: (% fibrosis / % tissue) * 100
        if (tissueAreaFraction > 0 && fibrosisAreaFraction >= 0) {
            percentageFibrosisOfTissue = (fibrosisAreaFraction / tissueAreaFraction) * 100;
        } else {
            percentageFibrosisOfTissue = 0;
        }
        
        // Store comprehensive results
        row = Table.size("Fibrosis_Results");
        Table.set("Image", row, filename, "Fibrosis_Results");
        Table.set("ROI", row, roiName, "Fibrosis_Results");
        Table.set("Area_ROI", row, roiArea, "Fibrosis_Results");
        Table.set("Area_Tissue", row, tissueArea, "Fibrosis_Results");
        Table.set("Area_Fibrosis", row, fibrosisArea, "Fibrosis_Results");
        Table.set("%_Tissue", row, tissueAreaFraction, "Fibrosis_Results");
        Table.set("%_Fibrosis", row, fibrosisAreaFraction, "Fibrosis_Results");
        Table.set("%_Fibrosis_of_Tissue", row, percentageFibrosisOfTissue, "Fibrosis_Results");
        Table.set("Threshold_Min_Tissue", row, minThreshold, "Fibrosis_Results");
        Table.set("Threshold_Max_Tissue", row, maxThreshold, "Fibrosis_Results");
        Table.set("Color_Space", row, "LAB", "Fibrosis_Results");
        Table.update("Fibrosis_Results");
        
        print("Results for " + roiName + ":");
        print("  - Percentage Tissue: " + tissueAreaFraction + "%");
        print("  - Percentage Fibrosis: " + fibrosisAreaFraction + "%");
        print("  - Percentage Fibrosis of Tissue: " + percentageFibrosisOfTissue + "%");
    }

    // Calculate and add perivascular fibrosis totals
    addPerivascularTotals(filename);

    // Save the single binary fibrosis image (only once per image, not per ROI)
    selectImage(fibrosisROI_ID);

    // Remove extension from filename
    if (indexOf(filename, ".") > 0) {
    baseName = substring(filename, 0, lastIndexOf(filename, "."));
    } else {
    baseName = filename;
    }

    saveAs("PNG", outputDir + "Fibrosis_Images" + File.separator + baseName + "_Fibrosis_Binary.png");
    close(); // Close the fibrosis binary image

    run("Clear Results");
    run("Select None");
}

function addPerivascularTotals(filename) {
    // Calculate totals for all perivascular fibrosis areas
    var totalROIArea = 0;
    var totalTissueArea = 0;
    var totalFibrosisArea = 0;
    var perivasularCount = 0;
    
    // Sum up all perivascular measurements
    for (i = 0; i < Table.size("Fibrosis_Results"); i++) {
        roiName = Table.getString("ROI", i, "Fibrosis_Results");
        
        // Check if this is a perivascular ROI
        if (indexOf(roiName, "Perivascular_") >= 0) {
            totalROIArea += Table.get("Area_ROI", i, "Fibrosis_Results");
            totalTissueArea += Table.get("Area_Tissue", i, "Fibrosis_Results");
            totalFibrosisArea += Table.get("Area_Fibrosis", i, "Fibrosis_Results");
            perivasularCount++;
        }
    }
    
    // Only add totals if there are perivascular ROIs
    if (perivasularCount > 0) {
        // Calculate total percentages
        var totalTissuePercentage = 0;
        var totalFibrosisPercentage = 0;
        var totalFibrosisOfTissuePercentage = 0;
        
        if (totalROIArea > 0) {
            totalTissuePercentage = (totalTissueArea / totalROIArea) * 100;
            totalFibrosisPercentage = (totalFibrosisArea / totalROIArea) * 100;
        }
        
        if (totalTissueArea > 0) {
            totalFibrosisOfTissuePercentage = (totalFibrosisArea / totalTissueArea) * 100;
        }
        
        // Add the total row to the Fibrosis_Results table
        row = Table.size("Fibrosis_Results");
        Table.set("Image", row, filename, "Fibrosis_Results");
        Table.set("ROI", row, "TOTAL_Perivascular_Fibrosis", "Fibrosis_Results");
        Table.set("Area_ROI", row, totalROIArea, "Fibrosis_Results");
        Table.set("Area_Tissue", row, totalTissueArea, "Fibrosis_Results");
        Table.set("Area_Fibrosis", row, totalFibrosisArea, "Fibrosis_Results");
        Table.set("%_Tissue", row, totalTissuePercentage, "Fibrosis_Results");
        Table.set("%_Fibrosis", row, totalFibrosisPercentage, "Fibrosis_Results");
        Table.set("%_Fibrosis_of_Tissue", row, totalFibrosisOfTissuePercentage, "Fibrosis_Results");
        Table.set("Threshold_Min_Tissue", row, "Combined", "Fibrosis_Results");
        Table.set("Threshold_Max_Tissue", row, "Combined", "Fibrosis_Results");
        Table.set("Color_Space", row, "LAB", "Fibrosis_Results");
        Table.update("Fibrosis_Results");
        
        print("TOTAL Perivascular Fibrosis Summary:");
        print("  - Number of perivascular areas: " + perivasularCount);
        print("  - Total ROI Area: " + totalROIArea);
        print("  - Total Tissue Area: " + totalTissueArea);
        print("  - Total Fibrosis Area: " + totalFibrosisArea);
        print("  - Total Tissue Percentage: " + totalTissuePercentage + "%");
        print("  - Total Fibrosis Percentage: " + totalFibrosisPercentage + "%");
        print("  - Total Fibrosis of Tissue: " + totalFibrosisOfTissuePercentage + "%");
    }
}

function saveProcessedImages(filename) {
    // Remove extension from filename once at the beginning
    if (indexOf(filename, ".") > 0) {
        baseName = substring(filename, 0, lastIndexOf(filename, "."));
    } else {
        baseName = filename;
    }
    
    // Save binary image
    selectImage(binaryImageID);
    saveAs("PNG", outputDir + "Binary_Images" + File.separator + baseName + "_Binary.png");
    
    // Save ROI overlay image
    if (roiManager("count") > 0) {
        // Create ROI overlay image
        selectImage(originalImageID);
        run("Duplicate...", "title=ROI_Overlay");
        
        // Set color and line width for EACH ROI individually
        for (j = 0; j < roiManager("count"); j++) {
            roiManager("Select", j);
            roiManager("Set Color", "black");
            roiManager("Set Line Width", 4);
        }
        
        // Show all ROIs
        roiManager("Show All");
        roiManager("Show All with labels"); // This ensures they're visible
        
        run("Flatten");
        saveAs("JPEG", outputDir + "ROI_Images" + File.separator + baseName + "_ROI_Overlay.jpeg");
        close();
        close(); // Close the duplicate
    }
}

function getImageFiles(fileList) {
    imageFiles = newArray();
    for (i = 0; i < fileList.length; i++) {
        if (endsWith(fileList[i], ".tif") || endsWith(fileList[i], ".tiff") ||
            endsWith(fileList[i], ".jpg") || endsWith(fileList[i], ".jpeg") ||
            endsWith(fileList[i], ".png") || endsWith(fileList[i], ".bmp")) {
            imageFiles = Array.concat(imageFiles, fileList[i]);
        }
    }
    return imageFiles;
}

function initializeResultsTables() {
    // Close existing tables
    if (isOpen("Results")) {
        selectWindow("Results");
        run("Close");
    }
    
    // Create tissue results table
    Table.create("Tissue_Results");
    
    // Create fibrosis results table
    Table.create("Fibrosis_Results");
}

function saveResults() {
    if (indexOf(filename, ".") > 0) {
        baseName = substring(filename, 0, lastIndexOf(filename, "."));
    } else {
        baseName = filename;
    }
    
    // Clear ImageJ's built-in Results table
    run("Clear Results");

    Table.save(outputDir + baseName + "_Tissue_Analysis_Results.csv", "Tissue_Results");
    Table.save(outputDir + baseName + "_Fibrosis_Analysis_Results.csv", "Fibrosis_Results");

    // Clear the custom tables after saving
    Table.reset("Tissue_Results");
    Table.reset("Fibrosis_Results");
}

function cleanupWindows() {
    // Close all image windows
    while (nImages > 0) {
        selectImage(nImages);
        close();
    }
    
    // Reset ROI Manager
    if (isOpen("ROI Manager")) {
        roiManager("Reset");
    }
}

// Run main function
main();
